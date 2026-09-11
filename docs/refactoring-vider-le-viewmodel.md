# Phase 2 du refactor — vider le ViewModel de son état publié

> **Statut** : cadrage validé le 2026-09-11, aucune ligne de code écrite.
> Rattaché à l'**axe F** de `ROADMAP.md` et au **§6** de `REFACTORING.md`, qui
> annonçait cette phase sans la cadrer. Ce document la cadre ; il ne la planifie
> pas — le découpage en tâches vient après (§8).

## 0. Pourquoi ce document existe

Le 2026-09-11, un **constat d'arrêt** a fermé la phase d'extraction de logique
pure : relevé sur le fichier, 337 fonctions dont 69 d'I/O et 151 qui mutent
l'état publié, et un plus gros calcul pur restant de **13 lignes**. Les
21 tranches précédentes avaient épuisé la matière ; les cinq dernières totalisent
−20 lignes de ViewModel.

Ce qui reste est l'**état publié** — et le §6 le disait déjà : *« les
135 propriétés publiées sont le vrai sujet »*. Le constat d'arrêt exigeait un
cadrage dédié avant d'ouvrir cette phase, parce qu'elle ne se décide pas au fil
d'une session d'extraction : elle touche la façon dont 45 vues obtiennent leur
état.

## 1. Deux buts, et ils n'ont pas le même mécanisme

C'est la distinction que tout le reste de ce document suit, et elle n'était pas
faite jusqu'ici :

| But | Ce qu'il exige | Ce qu'il n'exige pas |
| --- | --- | --- |
| **Testabilité** — l'état de domaine devient vérifiable | Que l'état vive dans un type inscrit aux `sources:` de `StarHubTHCore` | Que les vues changent quoi que ce soit |
| **Réactivité** — une vue ne se réinvalide que sur ce qu'elle lit | Que le mécanisme d'observation suive les propriétés, pas les objets | Que l'état change de fichier |

Les confondre a coûté cher. Deux des quatre stores déjà extraits
(`GameEnvironmentStore`, `NexusMetadataStore`) **relaient `objectWillChange`**
vers le ViewModel (`StarHubTHViewModel.swift:1982`, `:1988`) : ils ont gagné la
testabilité, et **perdu** sur le rendu — une écriture du store invalide
désormais toute la fenêtre en passant par deux objets au lieu d'un. Le code
l'assume comme provisoire ; ce document dit ce qui le remplace.

## 2. Le fait qui commande l'ordre — spike du 2026-09-11

L'application cible **macOS 14**, où la macro `@Observable` existe. Le spike
(programme jetable, `withObservationTracking` — l'API publique sur laquelle
SwiftUI s'appuie pour enregistrer ce qu'un `body` a lu) a mesuré six cas :

| | Cas | Résultat |
| --- | --- | --- |
| 1 | Lire une **façade** `vm.gameDir`, muter `store.gameDir` | **le suivi traverse** |
| 2 | Lire `vm.gameDir`, muter une autre propriété du **même store** | pas d'invalidation |
| 3 | Lire `vm.gameDir`, muter une autre propriété **du VM lui-même** | **pas d'invalidation** |
| 4 | VM `@Observable` lisant un store resté `ObservableObject` | **suivi perdu, en silence** |
| 5 | Tenir la référence sans lire de propriété | n'abonne à rien |
| 6 | Façade lisant un singleton non observable | pas de suivi |

Et trois faits, vérifiés en compilant ou en exécutant :

- `@ObservedObject` sur un type `@Observable` → **erreur de compilation**
  (« requires that 'X' conform to 'ObservableObject' »).
- `objectWillChange.send()` dans un type `@Observable` → **erreur de
  compilation** (« cannot find 'objectWillChange' in scope »).
- **La macro préserve les observateurs de propriété** — prouvé en exécutant un
  programme minimal : `didSet` voit `oldValue` et la nouvelle valeur, dans
  l'ordre. Décisif car **dix** `@Published` du VM portent un `didSet` ou un
  `willSet` — dont `viewingModDetail` (qui déclenche `loadModDetail`),
  `nexusCategories` (qui purge le cache de catégories) et `mods` — et ils
  survivront à la conversion tels quels. Sans cette preuve, dix points
  d'invalidation auraient été suspects à chaque passe.

**Le cas 3 est le pivot** : le défaut que le §6 attribuait aux 128 `@Published`
— « chaque `@Published` publie à toute la fenêtre » — **disparaît sans qu'un
seul d'entre eux change de fichier**. La réactivité ne dépend donc pas de
l'extraction. Elle dépend du mécanisme d'observation.

**Le cas 1 est ce qui rend le reste gratuit** : sous `@Observable`, une vue qui
lit `vm.gameDir` est suivie jusqu'à la propriété du store, *à travers la
façade*. Extraire un domaine cesse d'avoir un coût côté vues.

**Ce que le spike ne prouve pas** : il prouve le mécanisme qui déclenche le
rendu, pas le rendu. La vérification à l'écran reste due (§5, condition 4).

## 3. Chantier A — passer à `@Observable`

**Une seule passe, mécanique, aucun état déplacé.** Périmètre mesuré le
2026-09-11 :

| Élément | Nombre | Attrapé par le compilateur ? |
| --- | ---: | --- |
| `@Published` du ViewModel | 128 | — (à retirer) |
| `@Published` des trois autres classes du lot | **6** (`GameEnvironmentStore` 4, `NexusMetadataStore` 2, `SaveNotesStore` 0) | — (à retirer) |
| Classes à convertir | **4** | — (voir ci-dessous) |
| `@ObservedObject var vm:` dans les vues | **87** | **oui** |
| `@StateObject` de l'App | **1** (`vm`, L113 — `localization` L112 reste `@StateObject`, son type étant hors lot) | **oui** |
| `objectWillChange.send()` | 6 | **oui** |
| Bindings `$vm.…` (à passer en `@Bindable`) | 5 | **oui** |
| `didSet`/`willSet` sur `@Published` | **10** | **non** — mais prouvés préservés par la macro (§2, troisième fait) |

### Ce que le lot doit contenir — et ce qu'il peut laisser dehors

⚠️ **Première rédaction de ce document : « les huit `ObservableObject` passent
ensemble ». C'était faux, et cela doublait le coût annoncé.** Le cas 4 ne frappe
que les **façades de propriété** (`var gameDir: String { store.gameDir }`) : la
valeur transite par le VM, et si le store est resté en Combine, le suivi
s'arrête là. Il ne frappe **pas** un objet que le VM se contente de *tenir* et
qu'une vue observe pour lui-même — celui-là garde son propre mécanisme, quel
qu'il soit.

Relevé des huit `ObservableObject`, par ce critère :

| Classe | Déclarations directes dans les vues | Dans le lot ? |
| --- | ---: | --- |
| `StarHubTHViewModel` | 87 | **oui** — c'est le sujet |
| `GameEnvironmentStore` | **0** — façadé par le VM | **oui** (cas 4) |
| `NexusMetadataStore` | **0** — façadé par le VM | **oui** (cas 4) |
| `LocalizationStore` | 85, par paramètre | non |
| `ModListState` | 4, via `vm.modList` | non |
| `KeybindScanService` | 4, via `vm.keybindScan` | non |
| `SmapiInstaller` | 2, via `vm.smapiInstaller` | non |
| `BisectionRunner` | 2, via `vm.bisection` | non |

Les deux stores façadés sont exactement ceux qui portent un relais
`objectWillChange` — ce n'est pas une coïncidence : le relais **est** le symptôme
de la façade. S'y ajoute `SaveNotesStore` (une classe nue, pas un
`ObservableObject`), pour la raison exposée plus bas.

**Le lot atomique est donc : `StarHubTHViewModel`, `GameEnvironmentStore`,
`NexusMetadataStore`, `SaveNotesStore`.** Les cinq autres peuvent rester en
Combine indéfiniment, ou être converties plus tard une par une — leur
conversion ne dépend de rien et ne débloque rien.

**Pourquoi ce noyau-là reste atomique** : dès que le VM devient `@Observable`,
ses 87 sites `@ObservedObject` cessent de compiler d'un coup, et ses deux
façades perdent leur suivi en silence si les stores ne suivent pas. Ce
sous-ensemble ne se découpe pas ; le reste n'en fait pas partie.

C'est un big-bang, ce que le §7 de `REFACTORING.md` écarte en général. L'écart
est assumé ici pour une raison précise : **le risque d'un big-bang est
proportionnel à ce que le compilateur ne voit pas**, et ici il voit tout sauf
deux choses, toutes deux énumérables (ci-dessous). Le gate compile les
294 fichiers en un seul module : le lot se vérifie d'un bloc.

⚠️ Et cinq `ObservableObject` **subsistent volontairement** après le lot. La
règle à tenir n'est donc pas « plus aucun `ObservableObject` » — elle est
**« aucune façade du ViewModel ne pointe vers un `ObservableObject` »**. C'est
cette formulation-là que le cliquet doit porter (§5), et elle reste valable le
jour où l'un des cinq sera converti.

### Les deux angles morts, nommément

1. **Les chaînes mixtes** — éliminées par construction si les conversions du
   lot (VM + les deux stores façadés) sont dans le même commit. Verrouillé
   ensuite par un compteur de cliquet : plus aucune **façade** du VM ne doit
   pointer vers un `ObservableObject` (§5).
2. **Les façades lisant une source non observable** (cas 6). Le cas **trouvé**
   est `SaveNotesStore.shared`, lu par `savesHierarchy`, `availableFilterTags`
   et `getNote(for:)`, et republié à la main par `setAvatar`
   (`StarHubTHViewModel.swift:7195`), `setNote` (`:7335`) et deux sites de vue
   (`SavesView.swift:926`, `:958`). Sous `@Observable`, ces quatre
   `objectWillChange.send()` **cessent de compiler** — c'est le garde — mais les
   retirer sans rendre `SaveNotesStore` observable ferait cesser le
   rafraîchissement des notes et avatars. `SaveNotesStore` rejoint donc le lot.

⚠️ **« Trouvé », pas « seul » — et la différence est le principal angle mort de
ce document.** Ce cas a été rencontré en lisant le ViewModel pour autre chose ;
le recensement ci-dessus ne liste que les sites qui *appellent*
`objectWillChange.send()`. Une vue dont le rafraîchissement reposait sur une
invalidation globale, sans appel explicite, n'apparaît dans aucun grep.

**L'inventaire demandé est fait** (§3 bis) : 33 propriétés calculées de la
classe ont été lues une à une, et il a trouvé **une régression que le plan
aurait sinon découverte à l'écran**. Ce qu'il en reste à traiter est la
version corrigée de l'« étape 0 » de l'ordre des opérations.

### 3 bis. L'inventaire des propriétés calculées — fait le 2026-09-11

⚠️ **Ni 21 ni 25 : 33.** Le chiffre du cadrage était un `grep` sur accolade en
fin de ligne — il ratait `systemAlertCount: Int { … }` (accolade sur la même
ligne) et les façades vers les stores. Deuxième décompte raté de la même
manière que les 166 `@Published` comptés pour 135 : la règle du dépôt —
compter n'est pas lire — vaut pour les scripts de l'inventaire lui-même.
Chacune des 33 a été **lue**. Quatre autres propriétés calculées vivent dans
des types imbriqués (`producedNothing`, `isCapped` ×2, `errorDescription`) :
hors périmètre, elles ne dépendent d'aucun état observable.

**La synthèse que l'inventaire produit : le VM vit aujourd'hui d'un
*rafraîchissement par rebond*.** Sous `ObservableObject`, n'importe quelle
écriture d'n'importe quelle propriété re-rend toute vue observatrice, qui relit
donc **toutes** les propriétés calculées — y compris celles dont les sources
n'ont rien publié. Treize des trente-trois n'ont pas d'autre filet. Le cas 3 du
spike supprime ce rebond : c'est le but, et c'est précisément ce qui fera
apparaître ces treize-là.

| Famille | Sites | Remède |
| --- | --- | --- |
| **Couvert par le lot** — lit une source qui devient `@Observable` | 19, dont les 4 façades `gameDir`…, les façades `nexusMetadata`, `savesHierarchy`/`availableFilterTags` (la lecture `SaveNotesStore.shared.note(…)` devient trackée dès que le store entre dans le lot), `coreExtensionsSnapshot` (lit `mods`), et les dérivées d'état publié (`systemAlertCount`, `enabledMods`, `activeProfile`…) | Rien à faire |
| **UserDefaults / Trousseau** | 6 — `localAIEndpoint`, `localAIModelName`, `isLocalAIConfigured`, `deepLCredentials`, `isFallbackEnabled`, `defaultProfileId` | Le patron existe déjà : `hasDeepLKey` est **mémorisé** dans une propriété suivie, invalidée par le chemin d'écriture. Généraliser ; ne jamais interroger `UserDefaults` dans un corps calculé |
| **Service Combine hors lot** | 2 — `keybindProblemCount`, `healthIssues` (toutes deux lisent `keybindScanService.report`) | Voir ci-dessous — **la découverte de l'inventaire** |
| **Disque / PATH** | 4 — `unarInstalled`, `sevenZipInstalled`, `coreExtensionsSnapshot` (indirect), `smapiLogPath` (chemin dérivé du home, constant — rien à rafraîchir) | Rattrapé par le scan : le snapshot lit aussi `mods`, tracké — la valeur se recalcule au prochain scan. Dégradation minime, acceptée |

⚠️ **Limite de cet inventaire : il couvre les propriétés calculées, pas les
fonctions que les corps de rendu appellent.** `category(for:)` et
`sizeOnDisk(of:)` ont été vérifiées l'une après l'autre — la seconde lit
`modsFolderSizes` (tracké ✓), la première lit un cache dont le sort dépend de
l'étape 3 corrigée ci-dessus. Les autres n'ont pas été passées en revue : le
plan doit les traiter au contact, et la vérification à l'écran reste le filet
final (§5, condition 4).

**La découverte : `SystemAlertsView` afficherait un compte figé.** Mesuré, pas
déduit : elle observe `vm` et `localization`, **pas** `KeybindScanService`
(`SystemAlertsView.swift:36-37`). Aujourd'hui elle s'en tire par rebond — la
fin d'un scan de raccourcis ne mute aucune propriété du VM, mais le prochain
mouvement quelconque du VM la fait relire `healthIssues` frais. Après
conversion, elle ne se re-rend que si une propriété *trackée* lue par
`healthIssues` change — et la fin d'un scan keybind n'en change aucune :
**l'écran d'alertes et la pastille compteraient un rapport périmé,
indéfiniment.** `MainView` n'a ce problème que parce qu'elle observe
explicitement le service — son commentaire (`MainView.swift:6-10`) décrit le
même bug, déjà corrigé une fois, pour elle seule. Remède : donner à
`SystemAlertsView` la même observation explicite, ou mémoriser le compte
keybind dans une propriété suivie invalidée par le chemin d'écriture — le
patron `hasDeepLKey`, une deuxième fois.

**Ce que l'inventaire change à l'ordre des opérations** : l'« étape 0 »
n'est plus un inventaire à faire, mais **le traitement des 8 sites à remède**
(6 UserDefaults + 2 service) et l'ajout de `SystemAlertsView` à la liste de la
vérification à l'écran. Le lot atomique ne change pas : l'inventaire n'a trouvé
aucune source à ajouter — `SaveNotesStore` y était déjà, et c'est lui qui couvre
deux sites de plus qu'annoncé.

### Ordre des opérations

Le chantier se fait dans cet ordre, parce que chaque étape rend la suivante
vérifiable par compilation :

0. **Traiter les 8 sites à remède de l'inventaire (§3 bis)** — 6 lectures
   `UserDefaults`/Trousseau à mémoriser sur le patron `hasDeepLKey`, et les
   2 propriétés lisant `keybindScanService.report` — et ajouter
   `SystemAlertsView` à la liste de la vérification à l'écran.
1. Convertir les **quatre** classes du lot (`@Observable`, retrait des
   `@Published`, `final`) : `StarHubTHViewModel`, `GameEnvironmentStore`,
   `NexusMetadataStore`, `SaveNotesStore`. Le build casse — c'est voulu, et la
   liste des erreurs **est** la liste de travail.
2. Reprendre les 87 `@ObservedObject var vm` → propriété simple, l'unique
   `@StateObject` du VM (`StarHubTHApp.swift:113`) → `@State`, les 5 bindings
   → `@Bindable`.
3. Supprimer la **publication** des deux relais `objectWillChange`
   (`:1982`, `:1988`) — le cas 1 la rend inutile. ⚠️ **Pas leurs
   `AnyCancellable` sans examen : le relais `:1988` porte aussi la purge du
   `categoryCache` (`:1990`), et cette purge-là doit survivre.** Le cache est
   un `private var` stocké du VM : sous `@Observable` il devient tracké, donc
   la purge **est** l'invalidation des lignes rendues — la supprimer ferait
   rendre un cache périmé après chaque catégorie épinée, en silence.
   ⚠️ **Correction du 2026-09-11, par la rédaction du plan : le « sink
   muet » envisagé d'abord est inexécutable — `objectWillChange` disparaît du
   store avec la conversion elle-même.** Le remède est une **closure
   d'invalidation injectée** (`onInvalidate` sur `NexusMetadataStore`, appelée
   par `persistCategories()`/`persistModIds()`, que les cinq mutateurs
   empruntent) — testable en Core, là où le sink ne pouvait pas exister.
   Détail et code dans le plan, Task 4, étape 3.
4. Traiter les quatre rafraîchissements manuels restants.
5. Les deux gates, puis la vérification à l'écran — **la conversion reste
   atomique, la vérification commence par un seul écran** : le plus dense
   (`ModListView`), avec la liste des 8 sites à remède en tête d'affiche. Il
   n'existe pas de moyen de « convertir un seul écran » : les 87 sites cassent
   à la compilation d'un coup, c'est le prix de l'atomicité (§3) — ce qui se
   séquence, c'est la *constatation*, pas la conversion.

## 4. Chantier B — extraire les domaines en stores

Une fois A fait, le patron est celui de `GameEnvironmentStore`, **débarrassé de
son relais** :

```
Le ViewModel possède le store (`private let saves = SavesStore(...)`),
l'expose en façade (`var saves: [SaveGameInfo] { savesStore.saves }`),
et les vues ne changent pas — le suivi traverse (cas 1).
```

Ce qui suit du spike, et qui n'allait pas de soi : **aucune vue n'est touchée par
le chantier B**. Ni paramètre à propager, ni `@EnvironmentObject` à injecter.
La question qui avait ouvert ce cadrage — « comment une vue atteint-elle le
store ? » — n'a plus lieu d'être.

### Le tri des 128, qui n'est pas cosmétique

Le §6 pose la règle : l'état de **domaine** part au store, l'état de
**présentation** redescend en `@State` dans la vue qui le possède. Le relevé
du 2026-09-11 fait apparaître une **troisième catégorie** que la règle ne
prévoyait pas :

| Nature | Exemples | Destination |
| --- | --- | --- |
| **Domaine** | `mods`, `saves`, `logEntries`, `nexusUpdates`, `modProfiles`, `discovery` | Le store du domaine |
| **Présentation locale** | `editingSave`, `inventoryToEdit`, `saveToDuplicate`, `viewingSaveTimeline`, `showAlert` | `@State` de la vue |
| **Présentation *inter-vues*** | `pendingModFocus`, `pendingTranslationFocus`, `pendingConfigFocus`, `pendingModDetailFocus`, `pendingDetailTab`, `pendingLogFocus`, `pendingTabRequest`, `paletteRequested`, `pendingTranslationDiffFilter`, `reportDetailFocus` | **Ni l'un ni l'autre** |

Les dix `pending…` sont posés par une vue et consommés par une autre : les
faire redescendre en `@State` les rendrait inatteignables. Ils portent le
patron **B3-T4**, né d'un piège documenté — changer d'onglet remet cinq états de
détail à `nil` (`MainView.swift:232`), donc l'intention de navigation doit
survivre au changement d'onglet et être reconsommée dans le
`.onChange(of: currentTab)` lui-même. Ils vont dans un **store de navigation**
dédié, et la règle du §6 est complétée en conséquence.

### Ordre des domaines

Le critère reste celui du §5 — **ce sont les entrées qui décident** — complété
ici par un second : *combien de vues, hors les siennes, lisent cet état*.
Commencer par ce qui n'est lu que chez soi, finir par ce que tout le monde lit.

| Ordre | Domaine | Pourquoi là |
| --- | --- | --- |
| 1 | **Sauvegardes** (`saves`, `isSaveOperationRunning`, les trois préférences de vue) | ~560 l., `SaveManager`/`SaveTree` déjà en Core, et deux consommateurs seulement — `SavesView` et `CommandPaletteView` (relevé, la première rédaction affirmait « SavesView seule »). `SaveNotesStore` aura été rendu observable en A : le domaine arrive nettoyé |
| 2 | **Journal SMAPI** (`logEntries`, `smapiDiagnostics`, `smapiErrors`, `modErrorHistory`, …) | Le parseur est en Core depuis F1-T1 ; ne reste que l'état. Lu par `LogsView` et la pastille d'accueil — deux consommateurs connus |
| 3 | **Découverte** (8 propriétés) | Axe G récent, écrit d'un bloc, isolé par construction |
| 4 | **Entretien & corbeille** (`maintenanceReport`, `trashEvents`, `lastRepairReport`, `quarantineActionMessage`) | Petit, récent, déjà adossé à `MaintenanceInventory` et `DisabledModsCleanup` en Core |
| 5 | **Profils** | `ProfileActivation`, `ProfileRecovery`, `ProfileFactory`, `ProfileConfigCapture` sont déjà en Core : il ne reste que l'état et l'orchestration |
| 6 | **Traduction FR** | ~15 propriétés, logique close en Core depuis le 2026-09-11 |
| 7 | **Nexus** | ~20 propriétés, cinq types déjà en Core, mais le domaine est enchevêtré avec le réseau et l'installation |
| 8 | **Scan & parc** (`mods`, `scanProgress`, `duplicateIndex`, `modsFolderSizes`) | **En dernier, délibérément** : `mods` est lu par presque toutes les vues et par la moitié des autres domaines. C'est le seul dont l'extraction rate peut tout casser à la fois |

### Quand un domaine est-il extrait ?

Les quatre conditions du §6 s'appliquent telles quelles, avec un ajustement
rendu nécessaire par le chantier A :

- la condition 1 (« plus aucune de ses fonctions dans le ViewModel, pas même une
  façade ») est **assouplie** : sous `@Observable`, une façade ne coûte plus rien
  au rendu (cas 1). Une façade *de lecture* est donc acceptable à demeure ; une
  façade qui *décide* ne l'est pas ;
- les conditions 2 (tri des `@Published`), 3 (logique pure testée) et 4 (les deux
  gates + exercice manuel par l'auteur) sont inchangées.

## 5. Le filet

**Trois compteurs de cliquet**, dans l'esprit du verrou de taille posé le
2026-09-11 — une règle écrite que six chantiers ont ignorée n'est pas une règle :

| Compteur | Base | Ce qu'il interdit |
| --- | ---: | --- |
| `viewmodel_stored_state` | 128 → 0 | Que le ViewModel regagne de l'état à lui |
| `viewmodel_facades_to_combine` | 2 → 0 après A | Qu'une chaîne mixte réapparaisse (cas 4) — le seul angle mort silencieux. **Pas** « zéro `ObservableObject` » : cinq subsistent volontairement (§3). Ce qui doit rester à zéro, c'est le nombre de façades du VM déléguant à un objet Combine |
| `file:StarHubTH/StarHubTHViewModel.swift` | déjà posé, 10 212 | Que le fichier regrossisse |

Le deuxième est le plus important : il transforme un défaut invisible en échec
de build.

⚠️ **Le chantier A vide deux compteurs existants de leur sens, et il faut les
redéfinir dans le même commit — sans quoi le cliquet applaudira une régression.**
Sous `@Observable`, le mot-clé `@Published` disparaît du dépôt : compter les
`@Published` du ViewModel mesurerait **0 par construction**, sans rien protéger.
Deux conséquences :

- le compteur de la phase se compte sur les **propriétés stockées** du
  ViewModel (`var` sans corps calculé), d'où `viewmodel_stored_state` et non
  `viewmodel_published`. C'est lui qui mesure la phase : il ne peut que baisser,
  et une façade de lecture — désormais autorisée (§4) — ne le fait pas monter ;
- `published_without_private_set` (**68** à la base du 2026-09-11) tomberait à
  zéro mécaniquement, et le cliquet le lirait comme une amélioration. La règle
  qu'il porte — l'état ne se mute pas depuis l'extérieur — reste pourtant
  valable, et `private(set)` fonctionne tel quel sur une propriété
  `@Observable`. Le compteur doit donc être **réécrit** pour compter les
  propriétés observables sans `private(set)`, et sa base reposée à la valeur
  mesurée après conversion, pas à zéro.

Sans cette redéfinition, le chantier A ferait baisser trois compteurs d'un coup
et le dépôt enregistrerait un progrès là où il a seulement changé de vocabulaire.

⚠️ **Et `viewmodel_stored_state` doit se mesurer autrement qu'au `grep` nu.**
Distinguer une `var` stockée d'une `var` calculée demande de voir si la
déclaration est suivie d'un corps `{ … }`, sur un fichier de 10 212 lignes dont
les commentaires parlent abondamment des deux. Le cliquet a déjà payé cette
leçon — 166 `@Published` comptés pour 135 réels, 73 `UserDefaults` pour 52 —
et `check_standards.py` retire les commentaires avant de compter précisément
pour ça. Le compteur doit suivre la même règle, et son relevé être **vérifié à
la main** une fois contre une lecture du fichier avant d'être posé en base : une
base fausse verrouille un chiffre faux.

## 5 bis. Comment on saura que ça a marché

Les compteurs disent que l'état a bougé. Ils ne disent **rien** du but n°1, la
réactivité — et sans mesure avant/après, la phase pourrait s'achever sur « 0
état publié » sans que rien n'ait été gagné à l'écran.

Le dépôt a déjà le critère qu'il faut, et il est **rapporté par l'auteur sur son
parc réel** : **F3** (`ROADMAP.md`) — la latence de frappe dans la recherche de
la liste des mods. Trois raisons d'en faire le juge de cette phase :

- **le calcul y a été mesuré puis écarté** : filtrage ~2 à 5 ms par frappe, tri
  0,04 ms. « La piste restante est le **rendu**, pas le calcul » ;
- le constat joint à F3 décrit **exactement** ce que le cas 3 supprime :
  `healthIssues` recalculé à chaque accès et réévalué à chaque tick de
  `scanProgress` — par des vues qui ne lisent pas `scanProgress` ;
- **le témoin A/B existe déjà** : `bundles/StarHubFR_v1.11.1.zip`, la version
  d'avant B1-T2, que F3 désigne comme point de comparaison.

F3 est donc à traiter **avec** cette phase, pas à côté : son A/B est la mesure
de référence à prendre **avant** le chantier A, et la même manipulation après en
dira le gain. Si la frappe ne s'améliore pas, le but n°1 n'est pas atteint,
quels que soient les compteurs.

**Tests** : chaque store extrait est inscrit aux `sources:` de `StarHubTHCore`
et testé sur sa logique, pas son câblage — preuve rouge par sabotage (§4.2).
Un store qui n'apporte aucun test le dit dans son message de commit.

**Condition 4** : l'exercice manuel est dû à chaque tranche, et sur ce chantier
il a une cible précise — **chercher ce qui ne se rafraîchit plus**, pas ce qui
plante. C'est le profil de défaut que `@Observable` introduit.

## 6. Ce qu'on écarte, et pourquoi

**Le patron de l'amont (`@EnvironmentObject`)** — ils ont livré 8 stores + un
`AppCoordinator` qui ne publie rien, injectés en un point et déclarés par
111 `@EnvironmentObject`. Écarté pour deux raisons mesurées.

D'abord, **leur choix était contraint** : ils ciblent macOS 13 (`project.yml`,
`Info.plist`), où `@Observable` n'existe pas. Ce n'est pas une préférence
d'architecture qu'on pourrait reprendre par déférence — c'est la seule option
qu'ils avaient, et elle n'est pas la nôtre.

Ensuite, un `@EnvironmentObject` manquant n'est **pas vu par le compilateur** :
il échoue à l'exécution, sur l'écran qui le déclare. Or nous avons **deux scènes
`Window`** (`StarHubTHApp.swift:132` et `:232`), et une injection posée sur le
contenu de la première ne descend pas dans la seconde — chaque scène exige la
sienne. Le dépôt a d'ailleurs déjà tranché autrement à cet endroit :
`InstallReportWindow(vm:localization:)` reçoit ses deux dépendances **par
paramètre**. Ce n'est donc pas un obstacle infranchissable, c'est un coût
récurrent payé en défauts que le compilateur laisse passer — et ici, aucun agent
ne lance l'application : seul l'auteur peut les voir. Le patron retenu (§4) n'a
pas ce profil, puisqu'il ne touche pas aux vues du tout.

**Leur `AppCoordinator`** — sa bonne idée (« ne rien posséder, c'est ne jamais
pouvoir dériver de ce qu'on coordonne ») est retenue comme *cible* du ViewModel,
pas comme type à créer. Sous `@Observable`, un ViewModel qui ne garde que des
façades de lecture et de la composition **est** ce coordinateur. Créer une
classe de plus pour le dire déplacerait 45 vues sans rien gagner.

**Supprimer le ViewModel** — écarté par le §6, et rien ici ne le remet en cause :
sans filet de test sur l'UI, viser la suppression pousse au big-bang.

**Migrer les vues** — le cas 1 le rend inutile. C'est le principal acquis de ce
cadrage : la phase coûte une passe mécanique, pas une refonte des vues.

## 7. Risques

| Risque | Ce qui le contient |
| --- | --- |
| Une vue cesse de se rafraîchir sans erreur ni plantage | Le seul angle mort réel. Contenu par : la règle du cliquet « aucune façade du VM ne pointe vers un `ObservableObject` » (§5 — **pas** « zéro `ObservableObject` », cinq subsistent), les 8 sites à remède traités (§3 bis), et une condition 4 ciblée sur le rafraîchissement |
| Le chantier A casse le build longtemps | Assumé, et borné : 87 sites + 4 classes, tous désignés par le compilateur. Le build est incrémental (~30 s quand une signature du VM bouge, 59 s à froid) mais **chaque passe touche le VM**, donc aucune ne sera à 2,4 s : compter en dizaines de builds, pas en centaines |
| Le gain de réactivité est nul et personne ne s'en aperçoit | Le vrai risque du but n°1, et le seul que les compteurs ne voient pas. Contenu par le §5 bis : mesure A/B de F3 **avant** le chantier, même manipulation après |
| `@Observable` se comporte autrement dans SwiftUI que dans `withObservationTracking` | Non prouvé par le spike. C'est la première chose que la vérification à l'écran doit constater, sur un seul écran, **avant** de considérer le chantier clos |
| Le chantier B s'enlise comme les tranches 15-21 (−20 lignes pour cinq tranches) | Le critère de succès de B n'est pas le nombre de lignes mais `viewmodel_stored_state`, qui ne peut que baisser |

## 8. Découpage — ce que ce document ne fait pas

Le plan d'exécution (tâches, tests, ordre des commits) n'est pas ici. Il est
écrit — **`docs/superpowers/plans/2026-09-11-chantier-a-observable.md`**
(local, gitignoré comme tout ce dossier), et il couvre le **chantier A
seul** : la mesure A/B F3 en préambule, les 8 remèdes, la conversion atomique,
le cliquet, la vérification à l'écran. Sa particularité est connue d'avance :
**la conversion est atomique (§3), donc ce qui se séquence est la vérification,
pas le code**. Le chantier B fera un plan par domaine, dans l'ordre du §4.
Deux conventions du dépôt s'appliquent à l'ouverture : le tag
`pre-refactor-observable` posé par le plan (§4.6 de `REFACTORING.md` — c'est
ce qui rend le `git diff` final lisible et la marche arrière possible), et un
commit par étape.
