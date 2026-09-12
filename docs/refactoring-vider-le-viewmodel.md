# Phase 2 du refactor — vider le ViewModel de son état publié

> **Statut** : cadrage validé le 2026-09-11. **Chantier A livré et vérifié à
> l'écran le même jour** (13 commits, gate vert, 2 976 tests verts, contrôles
> de l'auteur OK). Le **chantier B est ouvert**. Reste dû, séparément : la
> mesure de latence **F3**, qui est un item de ROADMAP à part entière et non
> un contrôle de conformité. → **§9**.
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
vers le ViewModel (les sinks `environmentCancellable` et `nexusMetadataCancellable` du `init` — les numéros de ligne ici vieillissent mal, les noms non) : ils ont gagné la
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
| **Service Combine hors lot** | 1 vivant — `healthIssues` (lit `keybindScanService.report`). ⚠️ Le second du relevé initial, `keybindProblemCount`, était du **code mort** (zéro appelant, 4ᵉ instance de la famille « membres VM non câblés ») : supprimé au premier commit du chantier. Le remède vivant est le miroir `keybindReport` (plan, Task 1) | Voir ci-dessous — **la découverte de l'inventaire** |
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
   (`environmentCancellable`, `nexusMetadataCancellable`) — le cas 1 la rend
   inutile. ⚠️ **Il y en a un troisième depuis le chantier A : `keybindCancellable`
   (miroir `keybindReport`, Task 1 du plan) — lui doit **survivre** : le service
   reste hors lot, le miroir est ce qui suit son rapport après conversion.** ⚠️ **Pas leurs
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

### Domaine 1 — Sauvegardes, livré le 2026-09-11

Trois commits (`d3280b9`, `c6dbc8c`, `594e4e5`), gate exit 0, **2 987 tests
verts** (+11). Plan : `docs/superpowers/plans/2026-09-11-chantier-b1-savesstore.md`.

`SavesStore` (Core, `@Observable`) porte désormais **cinq** propriétés
stockées, les deux calculs de l'onglet et le verrou d'écriture. **Aucune vue
n'a été touchée** — le premier domaine du chantier B confirme le cas 1 à
l'usage, et pas seulement au spike : `SavesView`, `SaveTimelineView`,
`SaveCopySheets`, `MainView` et `CommandPaletteView` lisent les mêmes
`vm.saves`, `vm.savesHierarchy`, `vm.saveSortOption`… qu'avant.

| Descendue | Reste au VM, et pourquoi |
| --- | --- |
| `saves`, `isSaveOperationRunning`, `saveViewMode`, `saveSortOption`, `saveFilterTag` | `editingSave` et `viewingSaveTimeline` — **présentation inter-vues** : deux des cinq états que `MainView.swift:232` remet à `nil` au changement d'onglet. Elles vont au store de navigation, avec les dix `pending…` |
| `savesHierarchy`, `availableFilterTags` (les calculs) | `inventoryToEdit` — écrite par le `didSet` d'`editingSave`, elle suit celle-ci |
| | `saveToDuplicate`, `backupToBranch` — présentation locale, mais les faire redescendre en `@State` **toucherait des vues** |

**Deux points qui valent d'être repris pour les domaines 2 à 8 :**

1. **L'étiquette arrive en closure.** `hierarchy` filtre sur le tag d'une
   sauvegarde, qui vit dans `SaveNotesStore` (préférences). Injecter le magasin
   aurait rendu le filtre intestable sans écrire dans le vrai domaine ; une
   closure `tagForSave: (String) -> String` le rend testable **et préserve le
   suivi** — la lecture se fait à l'appel, donc dans le corps de rendu.
2. **Le verrou d'écriture devient un test-et-pose en une opération.** Huit
   fonctions écrivaient `guard !isSaveOperationRunning` puis
   `isSaveOperationRunning = true`. `beginOperation()` / `endOperation()` les
   remplacent : le refus concurrent est enfin sous test, et il reste
   exactement 8 prises pour 8 relâchements — un relâchement manquant figerait
   l'onglet en silence jusqu'au prochain lancement.

**Compteurs — prédits dans le plan, puis mesurés :**

| Compteur | Avant | Prédit | Mesuré |
| --- | ---: | ---: | ---: |
| `viewmodel_stored_state` | 168 | 163 | **163** ✓ |
| `observable_stored_without_private_set` | 123 | 122 | **122** ✓ |
| `viewmodel_facades_to_combine` | 0 | 0 | **0** ✓ |
| `our_shared_singletons` | 91 | 89 | **90** ✗ |
| `StarHubTHViewModel.swift` | 10 331 l. | — | **10 312 l.** |

⚠️ L'écart sur les singletons est la **prédiction** qui était fausse, pas le
code : les deux `SaveNotesStore.shared` retirés du ViewModel sont remplacés
par **un** dans la closure d'init du store. 91 − 2 + 1 = 90. Prédire chaque
compteur avant de le lire reste la bonne règle — c'est ce qui a fait voir
l'oubli.

**`SavesStore.swift` rejoint `LOT_FILES` de `check_standards.py` dans le commit
qui le câble.** Sans ça, l'état sorti du ViewModel échapperait à
`observable_stored_without_private_set` : le compteur aurait baissé de 4 sans
qu'aucune règle ne s'applique aux 3 propriétés arrivées ailleurs. **Chaque
domaine du chantier B doit le faire au même moment.**

**L'écart assumé — une dette, pas une condition remplie.** L'orchestration
d'I/O (`reloadSaves`, `editSave`, `saveInventory`, `deleteSave`,
`duplicateSave`, les quatre fonctions de backup) **reste au ViewModel** et
mute le store par `replace(saves:)` / `beginOperation()` / `endOperation()`.
La condition 1 assouplie autorise une façade de **lecture** à demeure ; ces
fonctions sont des verbes, et elles traversent `showModal` et `localization`.
Les descendre est une tranche à part, pas un oubli.

**Vérification à l'écran — OK, auteur, 2026-09-11.** Même angle mort que le
chantier A : une vue qui cesse de se rafraîchir sans erreur ni plantage. Les
six contrôles sont passés, dont les deux qui portaient — le filtre par
étiquette (le seul chemin qui exerce la closure `tagForSave` *et* le suivi à
travers elle) et la duplication (le verrou : un relâchement manquant aurait
figé l'onglet jusqu'au prochain lancement, en silence). Ce qui a été exercé :

1. l'onglet Sauvegardes s'affiche, en arbre **et** en grille ;
2. changer le tri (nom / dernière partie / argent) — l'ordre bouge ;
3. poser une étiquette sur une sauvegarde, puis filtrer dessus — la liste se
   réduit, et l'étiquette **apparaît** dans le menu de filtre ;
4. le bouton de rafraîchissement recharge la liste ;
5. dupliquer une sauvegarde — les boutons se désactivent pendant l'opération
   **et se réactivent après** (c'est le verrou : s'il reste pris, l'onglet est
   figé jusqu'au prochain lancement) ;
6. la palette de commandes (⌘K) trouve toujours une sauvegarde par son nom.

### Domaine 2 — Journal, tranche 1, livrée le 2026-09-11

Deux commits (`c6f408c`, `ef80744`), gate exit 0, **3 000 tests verts** (+13).
Plan : `docs/superpowers/plans/2026-09-11-chantier-b2-journal.md`.

**Le cadrage disait « deux consommateurs connus ». Il y en a huit**, dont un
qui n'est pas une vue : `LogsView`, `ModConflictSection`, `SystemAlertsView`,
`SmapiHealthCard`, `BisectionCard`, `SystemStatusFooter`, `ModDetailView` — et
`BisectionRunner.swift`, l'un des cinq `ObservableObject` restés en Combine.
Ce n'est **pas** une raison de rétrograder le domaine : le nombre de
consommateurs a cessé d'être un coût le jour où le cas 1 a été acquis. Ce qui
justifierait un report serait une dépendance vers un domaine non extrait — et
laisser l'orchestration au ViewModel la neutralise.

**La couture n'était pas celle que le cadrage annonçait.** `logEntries` n'est
pas un état « journal SMAPI » : 76 appels `log(…)` du ViewModel et 10 `vm.log(…)`
des vues y écrivent des entrées `.app`. Ce qui sépare les deux moitiés est
l'arithmétique du plafond — `smapiBudget = max(0, cap - appCount)` ne se teste
pas sans le compte des entrées de l'app. D'où :

| Unité | Contenu | État |
| --- | --- | --- |
| **Les entrées et leur plafond** | `logEntries`, `maxLogEntries`, `appendLogEntry`, `trimPreservingSignal`, la budgétisation | ✅ `LogBudget` (pur, 9 tests) + `LogStore` (`@Observable`, 4 tests) |
| **La santé SMAPI** | `smapiDiagnostics`, `smapiLogDate`, `smapiLogStale`, `smapiErrors`, `showSmapiAlerts`, `contentPatcherConflicts`, `modErrorHistory` + ses deux drapeaux, `lastLoggedSMAPIErrors` | tranche 2 |

**Le gain est la mise sous test de deux bugs réels**, que les commentaires du
ViewModel décrivaient sans qu'aucun test ne les retienne : un rechargement qui
**empilait** une copie entière du journal SMAPI (N copies après N lancements),
et un écrêtage par la **tête** du tableau combiné qui effaçait tout le journal
de l'app dès que le journal SMAPI était gros. Le *quoi jeter*, lui, était déjà
couvert (`LogNoise.trimIndices`) — seule la composition manquait.

⚠️ **Une vue a été touchée, contre la règle du chantier, et c'est le
compilateur qui l'a exigé.** `LogsView` faisait
`vm.logEntries.removeAll { $0.source == .app }`. **Mon relevé d'écritures
cherchait `vm.<propriété> =` et ne voyait pas les mutations par méthode** —
à refaire autrement pour les domaines 3 à 8 : une façade en lecture seule
transforme le défaut en erreur de compilation, mais seulement si l'on sait
qu'il faut s'y attendre. « Vider les journaux » est descendu dans le store
(`clearApp()`), et il **garde** le bloc SMAPI : l'effacer ne ferait que le
faire revenir au prochain rechargement, et entre-temps la liste contredirait
la carte de santé.

⚠️ **Un changement de comportement, assumé** : la passe d'imputation
(`dismissingUnknownInferredMods`) s'applique désormais aux entrées écrêtées au
plafond global, non plus au budget restant. On impute donc quelques lignes de
plus que nécessaire, jamais moins — et cette passe ne change aucune ligne,
elle retire un lien mort.

**Compteurs — trois prédictions, trois justes** (contre quatre sur cinq au
domaine 1) : `viewmodel_stored_state` 163 → **162**,
`observable_stored_without_private_set` 122 → **121**,
`viewmodel_facades_to_combine` **0**. ViewModel 10 312 → **10 297** lignes.
Cliquet resserré dans le commit de câblage.

**Vérification à l'écran — OK, auteur, 2026-09-11.** Les cinq contrôles sont
passés, dont les deux qui portent les bugs historiques (2 et 3). Ce qui a été
exercé :

1. l'onglet Journaux affiche des lignes, app **et** SMAPI ;
2. **le bouton de rechargement ne duplique pas le bloc SMAPI** — le compte
   reste stable d'un rechargement à l'autre (premier bug historique) ;
3. **après un rechargement sur un gros journal, les lignes StarHubFR sont
   toujours là** (second bug historique) ;
4. « Vider les journaux » retire les lignes de StarHubFR **et garde** celles de
   SMAPI ;
5. la carte de santé SMAPI et la pastille d'alertes affichent toujours leur
   compte.

### Domaine 2 — Journal, tranche 2 (santé SMAPI), livrée le 2026-09-11

Trois commits (`7ce32ca`, `6c7b4d9`, `f2dd895`), gate exit 0, **3 020 tests
verts**. `SmapiHealthFold` (pur, 12 tests) + `SmapiHealthStore`
(`@Observable`, 8 tests). ViewModel 10 297 → **10 288** ;
`viewmodel_stored_state` 162 → **154**.

**Une propriété morte trouvée par le relevé lui-même.** `showSmapiAlerts`
n'avait qu'une occurrence dans tout le dépôt : sa déclaration. Née le
2026-07-03 avec la fonctionnalité, jamais touchée depuis. Cinquième instance
de la famille « membre du ViewModel non câblé » — et elle n'a été vue que
parce que le relevé des écritures, préalable au déplacement, a rendu **zéro**.
Supprimée dans son propre commit, pour que la baisse d'un point reste lisible.

**Ce que le store garantit, et que trois affectations voisines ne
garantissaient que par convention** : date, diagnostics et conflits viennent
d'une même lecture et changent ensemble. Un commentaire du ViewModel le
demandait déjà ; c'est désormais la signature qui l'impose. Effet de bord
bienvenu : au rechargement, les conflits étaient publiés *après*
`recordErrorHistory`, donc dans un second temps — ils le sont maintenant dans
le même appel que la date.

**Deux règles d'accumulation, enfin sous test.** Le diff des alertes se fait
par **contenu** et non par compte (une alerte remplacée par une autre laisse le
compte inchangé) ; un journal **sans date** n'est jamais replié dans
l'historique, et un journal déjà replié non plus — sans quoi chaque ouverture
d'onglet gonflerait les compteurs. Deux branches sont **conservées telles
quelles, pas déduites** — le jeu de référence n'est pas réécrit quand rien
n'est neuf, et un `reset()` ne l'oublie pas : leurs tests disent ce que le code
fait, pas qu'il a raison.

⚠️ **Un sabotage n'a rien rougi, et c'était le test qui avait tort.** Celui de
l'ordre de journalisation : à trois éléments, l'ordre du `Set` avait coïncidé
avec celui du journal. Renforcé à huit — probabiliste contre un sabotage,
jamais contre du code correct, et c'est écrit dans le test.

⚠️ **La prédiction des compteurs a raté d'un point, pour la deuxième fois
aujourd'hui, et de la même façon** : elle compte ce qui **part** du ViewModel
et oublie ce que le code neuf **ajoute** (au domaine 1, le `.shared` de la
closure ; ici, `loggedAlerts`, une `private var` du store). **Prédire le
solde, pas le départ.**

**Reste dû sur ce domaine — tranche 3** : l'historique d'erreurs par mod
(`modErrorHistory`, `lastErrorHistoryLogDate`, `errorHistoryLoaded`). Il n'est
pas ici parce qu'il est muté par méthode en trois endroits du ViewModel
(`merge`, `ModFolderRename.migrate(&…)`, `remove`) et qu'il a sa propre
persistance (`ModErrorHistoryStore`) : c'est un sous-domaine, pas un reste.
`SmapiHealthFold.observations` l'attend déjà, testée.

**Vérification à l'écran — OK, auteur, 2026-09-11.** Les quatre contrôles
sont passés, dont les deux qui portent (le verrou du bouton de relecture, et
l'absence de re-journalisation des mêmes alertes). Ce qui a été exercé :

1. la carte de santé SMAPI affiche sa version, ses mods ignorés, ses alertes ;
2. le bouton de relecture de la page des alertes système tourne **et se
   réactive** (le verrou : s'il reste pris, le bouton est mort jusqu'au
   prochain lancement) ;
3. relancer la relecture deux fois de suite n'ajoute **pas** une seconde fois
   les mêmes alertes dans l'onglet Journaux ;
4. la section des conflits Content Patcher affiche toujours ses conflits, avec
   la date du journal.

### Domaine 2 — Journal, tranche 3 (historique d'erreurs), livrée le 2026-09-11

`ErrorHistoryStore` (Core, `@Observable`, 13 tests, **six sabotages**).
ViewModel 10 288 → **10 266** ; `viewmodel_stored_state` 154 → **151**.
Gate exit 0, **3 031 tests verts**.

**Ce que l'extraction achète ici n'est pas de la testabilité : c'est une garde
qui cesse d'être facultative.** Tant que l'historique n'a pas été lu du
disque, rien ne doit le muter — le muter reviendrait à écrire un historique
vide par-dessus le fichier, et cet historique **ne se rebâtit pas** (le
journal SMAPI suivant écrase le précédent). La règle vivait sous forme de deux
`if errorHistoryLoaded` **posés au point d'appel** : un troisième appelant
aurait pu l'oublier, et la perte ne se serait vue qu'au lancement suivant. Le
type la tient maintenant, et aucun appelant ne peut la contourner.

`recordErrorHistory` passe de 30 lignes à 12 : `SmapiHealthFold`, extrait à la
tranche 2, l'attendait. Ce qui reste au ViewModel est exactement ce qui a
besoin du parc.

**Un détail de `@Observable` qui coûte une compilation** : `private lazy var`
ne compile pas dans une classe `@Observable` — la macro en fait une propriété
calculée (« 'lazy' cannot be used on a computed property »). Un store qui a
besoin d'un crochet vers son propriétaire le reçoit donc **après**
construction, patron déjà tranché par `NexusMetadataStore.setOnInvalidate`.

⚠️ **Troisième écart d'un point sur la prédiction des compteurs, troisième
fois la même cause — et cette fois le remède est outillé.** Je compte de tête
ce que le code neuf ajoute et j'oublie toujours une propriété (ici `isLoaded`,
au domaine 2 `loggedAlerts`, au domaine 1 le `.shared` de la closure).
`check_standards.py` porte déjà `class_members_with_lines`, qui énumère les
stockées d'un fichier avec leur `private(set)` : **c'est lui qui doit prédire
le solde**, pas moi. À faire ainsi dès le domaine 3.

**Le domaine 2 est clos pour son état.** Ce qui reste au ViewModel est de
l'orchestration : `log(_:level:)`, `loadSmapiLog`, `parseSMAPILog`,
`parseAndAppendSmapiLog`, `recordErrorHistory` — toutes des verbes, et les
deux dernières lisent `mods`, donc le domaine Scan, extrait en dernier.

**Vérification à l'écran — due, auteur.** Trois contrôles, tous sur la fiche
d'un mod (onglet Mods → un mod qui a déjà journalisé des erreurs) :

1. l'historique d'erreurs de la fiche affiche toujours ses lignes ;
2. renommer le dossier d'un mod **conserve** son historique sous le nouveau
   nom ;
3. jeter un mod à la corbeille fait disparaître son historique.

### Domaine 3 — Découverte, livrée le 2026-09-11

Trois commits (`8ce5e06`, `f50b883`, `a32deda`), gate exit 0, **3 039 tests
verts**. `DiscoveryStore` (`@Observable`, 8 tests, cinq sabotages). ViewModel
10 266 → **10 246** ; `viewmodel_stored_state` 151 → **143**.

**Ce que l'extraction achète ici est un compteur qui cesse d'exister en
double.** `pendingSectionFetches += 1 ; discoveryLoading = true`, puis
`max(0, …-1) ; if == 0 { discoveryLoading = false }`, était écrit **deux fois
verbatim** — un compteur et son drapeau, dupliqués, c'est la forme exacte des
divergences que ce dépôt a déjà payées (quatre copies d'`isOsJunk`, dont une
amputée). Trois règles jusque-là muettes sont maintenant épinglées : le voyant
ne s'éteint qu'à la **dernière** réponse ; le plancher à zéro défend contre un
rappel en trop, qui laisserait le voyant allumé au chargement suivant ;
« toutes catégories » (`nil`) est une **identité**, pas un joker.

**Le relevé du cadrage disait « 8 propriétés » ; l'outil en compte onze**, et
trois d'entre elles ne sont pas du domaine :

| Reste au ViewModel | Pourquoi |
| --- | --- |
| `discoveryEpoch`, `discoveryDetailEpoch` | des jetons que l'orchestration réseau ouvre et vérifie, pas de l'état affiché |
| `recentNexusInstalls` | malgré son voisinage dans le fichier, elle est écrite par une **installation**, retirée par une désinstallation, et lue par `installedNexusIds()` que trois zones consultent — elle n'est pas de la vitrine |
| `discoveryRows`, `loadDiscovery`, `fetchDiscoverySection`, les recherches, la fiche | de l'orchestration : réseau (`NexusSearchClient`), cache disque (`ModCatalog`), et `discoveryRows` lit `mods` — donc le domaine Scan, extrait en dernier |

**Trois types sont entrés en Core avant le store** : `NexusSearchError` (qui
vivait dans `NexusSearchClient`, fichier de réseau — un store testable ne peut
pas en dépendre ; l'ancien nom reste un **alias**, aucun des huit appelants ne
change), `DiscoverySearchResult` et `DiscoveryDetailState`, tous deux imbriqués
dans le ViewModel. `DiscoveryRow` **reste** un alias du ViewModel : son
commentaire dit qu'il tient les vues en place jusqu'au découpage des vues.

⚠️ **Une ligne de vue touchée** (`DiscoverView:155`), qui nommait
`StarHubTHViewModel.DiscoverySearchResult` : un alias n'était pas possible —
le build réel compile un seul module, donc `typealias X = X` serait circulaire.

⚠️ **Un sabotage n'a d'abord rien rougi parce qu'il cassait la
compilation**, ce qui n'est pas une preuve rouge : un test qui ne compile pas
ne dit rien du mécanisme. Refait par **suppression du garde** plutôt que par
substitution d'une expression invalide, il rougit son test. À retenir : un
sabotage doit produire du code **valide et faux**, jamais du code invalide.

✅ **La prédiction des compteurs est juste pour la première fois, sur les
deux** — parce qu'elle a été faite par `class_members_with_lines` sur le
ViewModel et sur les `LOT_FILES`, au lieu d'énumérer de tête. C'est la méthode
à garder pour les domaines 4 à 8.

**Vérification à l'écran — OK, auteur, 2026-09-11.** Les quatre contrôles
sont passés, dont celui qui porte (le voyant de chargement s'éteint — c'est le
compteur de requêtes en vol). Ce qui a été exercé :

1. les trois sections se remplissent, et le voyant de chargement **s'éteint**
   (c'est le compteur : s'il passe sous zéro, il resterait allumé au
   chargement suivant) ;
2. choisir une catégorie filtre les sections ; rechoisir la même ne relance
   rien ; revenir à « toutes » les rouvre ;
3. une recherche par nom rend ses résultats, « voir plus » en ajoute sans
   boucler, et fermer la recherche rend la vitrine ;
4. ouvrir la fiche d'un mod l'affiche, la refermer et en ouvrir une autre
   n'affiche pas la précédente.

### Domaine 4 — Entretien & corbeille, livré le 2026-09-11

Deux commits (`b96d3c9`, `d8db57b`), gate exit 0, **3 046 tests verts**.
`MaintenanceStore` (`@Observable`, 7 tests, trois sabotages). ViewModel
10 246 → **10 252** (⚠️ +6, voir plus bas) ; `viewmodel_stored_state`
143 → **138**.

Les quatre calculs du domaine étaient déjà en Core et testés
(`MaintenanceInventory`, `ModFolderRepairer`, `ModTrash`,
`DisabledModsCleanup`) — il ne restait que l'état et le verrou de
construction, devenu test-et-pose. Deux distinctions épinglées qui ne
l'étaient pas : `report` a `nil` tant que l'inventaire n'est pas construit,
**distinct** d'un rapport vide (« rien à faire ») ; `setTrashEvents`
**remplace** en bloc, la corbeille étant relue du disque à chaque demande.

⚠️ **Deux façades sont `get`+`set`, et ce n'est pas un choix.**
`QuarantineView` **écrit** l'état du domaine directement — quatre
`vm.quarantineActionMessage = …` et un `vm.lastRepairReport = nil`. Le
relevé des écritures (leçon `LogsView`, domaine 2) les a trouvés **dans la
vue** avant le gate ; les façades ont été écrites en conséquence, et aucune
vue n'a bougé.

⚠️ **Le verrou de taille du ViewModel monte de 6 lignes (10 246 → 10 252),
assumé et explicite dans le diff du cliquet.** Les deux façades `get`+`set`
coûtent plus de lignes que les cinq déclarations retirées. Les compteurs que
le chantier mesure sont **l'état**, et ils baissent tous ; la ligne brute est
le prix de ne pas toucher la vue. **Si le domaine 5 reproduit ce profil, la
question d'une reprise des vues (P8) se reposera au cas par cas** : une façade
`get`+`set` est le signe qu'une vue écrit de l'état de domaine, et le vrai
remède est de lui donner un verbe nommé — pas d'écrire le champ nu.

**Vérification à l'écran — OK, auteur, 2026-09-11.** Les quatre contrôles
sont passés, dont les deux qui portent (le verrou du bouton de construction,
et la bannière de réparation que rien n'efface à tort). Ce qui a été exercé :

1. construire l'inventaire affiche son rapport, le spinner tourne **et se
   réactive** (le verrou) ;
2. réparer un dossier cassé affiche la bannière de réparation ; relancer un
   scan **sans** réparation ne l'efface pas (c'est la garde
   `setRepairReport(nil)` : seuls « vide + rien à voir » l'effacent) ;
3. vider la quarantaine affiche son message vert ; le message d'erreur rouge
   s'affiche si l'opération échoue ;
4. la corbeille affiche ses événements, un geste de remise/purge la
   rafraîchit **en remplaçant** la liste (pas de doublon).

### Domaine 5 — Profils, livré le 2026-09-11

Trois commits (`da2119e`, `0f8dce6`, et celui-ci), gate exit 0, **3 056 tests
verts**. `ProfileStore` (`@Observable`, 10 tests, deux sabotages). ViewModel
10 252 → **10 269** (⚠️ +17) ; `viewmodel_stored_state` 138 → **134**.

Les décisions étaient déjà en Core (`ProfileActivation`,
`ProfileConfigCapture`, `ProfileRecovery`, `ProfileFactory`) — il ne restait
que l'état. Ce que l'extraction achète : le **lookup** `profile(with:)`,
réécrit dix fois en `first(where:)` dans le ViewModel ; `activeProfile` sans
risque d'identifiant orphelin ; et `endApplying()`, qui efface **ensemble** le
drapeau de verrou et l'identité du spinner — posés, eux, à deux rythmes
différents (aiguillage puis orchestration).

⚠️ **Le relevé des écritures a manqué six sites, une troisième fois — et le
profil du trou est maintenant clair.** Ni un grep des `=`, ni un relevé des
`append` ne voient les **mutations par indice** : `modProfiles[i].x = …`,
`.merge(…)`, `.setNote(…)`, six sites sur quatre fonctions. Le store gagne
`add`, `removeProfile(with:)` et `mutateProfile(with:_:)` (inout, `false` si
le profil manque). **La règle pour les domaines 6 à 8 : grepper tout ce qui
méthode ou indice sur la propriété**, pas seulement les affectations — c'est
le compilateur qui l'a trouvé, trois domaines de suite.

⚠️ **Verrou de taille +17 lignes (10 252 → 10 269), deuxième domaine de suite
en hausse brute.** Cette fois sans une seule façade `get`+`set` : ce sont les
closures `mutateProfile`, intrinsèquement plus longues que l'affectation par
indice. Les compteurs de l'axe baissent (134, 109) — la ligne brute ne mesure
pas ce que ce chantier déplace. **La reprise des vues (P8) mérite maintenant
une vraie tranche** : chaque façade du ViewModel est une ligne que la vue
pourrait lire sur le store directement.

`profileManagedConfigMods` **reste** au ViewModel : c'est un magasin persisté
(load/save, migrations, purges), le voisinage de `favoriteMods` et
`blacklistedMods` — pas l'état de ce domaine.

**Vérification à l'écran — OK, auteur, 2026-09-11.** Les cinq contrôles sont
passés, dont les deux qui portent (le couple drapeau/identité qui disparaît
ensemble, et le verrou anti double activation). Ce qui a été exercé :

1. créer un profil — il apparaît ; le renommer garde ses mods ;
2. activer un profil — le spinner remplace le bouton de la ligne pendant
   l'opération, **et les deux disparaissent ensemble** à la fin (c'est
   `endApplying`) ;
3. activer un second profil pendant que le premier tourne est impossible
   (les boutons sont désactivés — le verrou) ;
4. supprimer le profil actif — aucun profil actif à l'écran, pas de nom
   fantôme dans le pied de page ;
5. ajouter une dépendance manquante à un profil (fiche d'un mod) — elle
   entre dans la liste du profil sans toucher les autres.

### Domaine 6 — Traduction FR, tranche 1 (le hub), livrée le 2026-09-11

Trois commits (`ff1a125`, `3273926`, et celui-ci), gate exit 0, **3 063 tests
verts**. `TranslationHubStore` (`@Observable`, 7 tests, trois sabotages).
ViewModel 10 269 → **10 295** (⚠️ +26) ; `viewmodel_stored_state` 134 → **129**.

Le domaine était composite — la reconnaissance en trouve **cinq familles**
là où le cadrage en voyait une :

| Famille | Propriétés | État |
| --- | --- | --- |
| **Le hub communautaire** | `installedTranslations`, `translationHits`, `translationInstalledHits`, `searchingTranslations`, `busyTranslations` | ✅ cette tranche |
| **La couverture d'un profil** | `profileTranslationSummaries`, `profileTranslationCoverage`, `profileTranslationTask`, `profileTranslationCacheEntries`, `profileTranslationCacheLoaded`, `isMeasuringProfileTranslation` | tranche 2 |
| **Les réglages IA/DeepL** | `localAI*`, `deepL*`, `batchProgress`, `batchReport`, `batchTask` | reste — **miroirs synchrones du chantier A**, leur déplacement reprendrait ce câblage |
| **Le thaï** | `thaiTranslations`, `thaiTranslationsError` | reste — fonctionnalité upstream distincte |
| **Hors domaine** | `staleTranslationMods` (écrit par le **scan**), `pendingTranslation*` (navigation), `renamePairsCache` (X60) | reste |

Les règles épinglées par le store : une recherche rend **deux moitiés** (les
propositions et ce qui est posé — la moitié posée porte la pastille de mise à
jour, la jeter la faisait disparaître) et se vide **ensemble** ;
`setHits(nil)` **retire la clé** plutôt que de cacher un tableau vide ; les
vols sont des **ensembles** mod par mod, pas des drapeaux.

**14 mutations du registre** passent par `mutateInstalled { … }` — les
blocs miroirs (record + forgetAddon + recordAddon, deux exemplaires
identiques) dans une closure unique. La persistance reste à l'appelant, qui
lit la façade. Trois gardes `guard registry.<mutating>(…)` deviennent
var + mutate + guard : plus verbeux, mais l'écriture a un point nommé.

⚠️ **Verrou de taille +26 lignes, troisième domaine de suite.** Les closures
ajoutent de l'indentation à chaque bloc miroir. **Constat consigné : la
ligne brute du ViewModel ne redescendra plus beaucoup tant que ses façades
restent nombreuses — la reprise des vues (P8) doit devenir une tranche de
son côté**, sinon le chantier continuera d'échanger des lignes contre de
l'état gouverné.

**Vérification à l'écran — OK, auteur, 2026-09-11.** Les cinq contrôles sont
passés, dont celui qui porte (deux recherches successives n'héritent rien
l'une de l'autre — les deux moitiés se vident bien ensemble). Ce qui a été
exercé :

1. chercher une traduction — la recherche tourne (le bouton de la fiche est
   désactivé), les autres fiches restent utilisables pendant ce temps
   (l'ensemble mod par mod) ;
2. les résultats s'affichent ; si une traduction est déjà posée, elle sort
   des propositions et apparaît comme « posée » avec sa mise à jour éventuelle ;
3. rattacher un résultat Nexus — il **change de moitié** (proposition →
   posée) sans nouvelle requête ;
4. retirer une traduction — les propositions reviennent, le registre survit
   à un redémarrage ;
5. deux recherches de suites sur deux mods différents — la seconde
   n'hérite rien de la première (les deux moitiés se vident ensemble).

### Domaine 6 — Traduction FR, tranche 2 (la couverture de profil), livrée le 2026-09-12

Deux commits (`0942fca` pour le store, et celui-ci pour le câblage), gate
exit 0, **3 070 tests verts**. `ProfileTranslationStore` (`@Observable`,
7 tests, trois sabotages). ViewModel 10 295 → **10 288** ;
`viewmodel_stored_state` 129 → **123** ;
`observable_stored_without_private_set` 109 → **105**.

**Première baisse de ligne brute depuis quatre domaines.** Elle ne dit pas
que le constat de la tranche 1 était faux — elle dit d'où venait la hausse :
ce domaine-ci n'a livré **aucune façade `get`+`set`** (les deux vues qui
lisent l'état ne l'écrivent pas), là où Entretien et Profils en devaient
plusieurs. Le diagnostic tient : c'est la façade en écriture qui coûte, et
la reprise des vues (P8) reste la tranche à faire.

🚩 **La `Task` n'était pas un verrou, elle en tenait lieu.**
`refreshProfileTranslationCoverage` gardait sur la non-nullité de
`profileTranslationTask`, et cette `Task` n'a **jamais** été annulée nulle
part — elle n'était retenue que pour qu'on puisse tester si elle existait. Le store porte maintenant un vrai
test-et-pose (`beginMeasure()` rend `false` si une passe tourne), la `Task`
détachée n'est plus retenue du tout, et le verrou a une obligation que
l'ancienne forme n'avait pas : **le rendre sur le chemin « rien à mesurer »**.
Ce chemin sortait auparavant avant même de poser le drapeau ; en remontant
le verrou en tête, l'oublier aurait figé le témoin jusqu'au prochain
lancement. Le sabotage qui le prouve est le second appel à `beginMeasure()`.

⚠️ **L'écriture disque sort du store, délibérément.** Le premier jet lui
injectait *deux* closures (lire, écrire) ; l'écriture a été retirée.
`pruneCache(keeping:)` élague l'état et **rend** ce qui reste, l'appelant
écrit hors du fil principal — comme le faisait déjà le ViewModel. Un store
qui écrit ne dirait pas *quand* : l'appelant, lui, sait que l'écriture suit
la passe et non chaque invalidation. Effet de bord honnête : le faux cache
des tests perd son `save`, devenu mort.

Deux distinctions préservées du ViewModel et consignées dans le store :
`coverage` est en `@ObservationIgnored` (interne de travail — le signal de
rendu est `summaries`, et observer les deux ferait redessiner la page à
chaque mod mesuré), et le cache est lu **une fois par session** y compris
quand l'URL manque (sans quoi chaque affichage de la page réessaierait un
Application Support qui ne deviendra pas trouvable).

`summary(for:)` était sans appelant à la sortie du store ; le
`translationSummary(for:)` du ViewModel lui délègue désormais — une fonction
publique sans appelant passe les revues sans bruit, le dépôt en a déjà
collectionné plusieurs.

`ProfileTranslationStore.swift` entre dans `LOT_FILES` de `check_standards.py`
(ses cinq stockées sont déjà `private(set)`, le compteur ne bouge pas) : hors
du lot, un store peut relâcher la règle que le cliquet protège.

**Vérification à l'écran — OK, auteur, 2026-09-12.** Les quatre contrôles
sont passés. Ce qui a été exercé :

1. ouvrir la page des profils sur un parc jamais mesuré — le **témoin**
   s'affiche pendant la passe, pas un pourcentage faux, puis les
   pourcentages le remplacent ;
2. quitter la page et y revenir **pendant** la mesure — aucune seconde passe
   ne démarre (le verrou), et le témoin ne reste pas allumé ;
3. traduire un mod contenu dans un profil, puis rouvrir la page — le
   pourcentage de ce profil **a bougé** (l'invalidation par `UniqueID`) ;
4. relancer l'application — la page s'affiche sans nouvelle analyse longue
   (le cache de session relu du disque), et un profil dont un mod a été
   désinstallé ne traîne plus son entrée.

### Domaine 7 — Nexus, tranche 1 (les mises à jour), livrée le 2026-09-12

Deux commits (`110dfa8` pour le store, et celui du câblage), gate exit 0,
**3 082 tests verts**. `ModUpdateStore` (`@Observable`, 11 tests, huit
sabotages). ViewModel 10 288 → **10 270** (−18) ;
`viewmodel_stored_state` 122 → **114** ;
`observable_stored_without_private_set` 104 → **99**.

🚩 **Le cadrage annonçait ~20 propriétés ; le relevé en trouve 28**, et le
domaine est composite comme le 6. Cinq familles :

| Famille | Propriétés | État |
| --- | --- | --- |
| **Les mises à jour** | `nexusUpdates`, `snoozedUpdates`, `affirmedUpdates`, `unverifiableMods`, `isCheckingNexusUpdates`, `nexusCheckError`, `nexusCheckProgress`, `nexusFallbackInFlight` | ✅ cette tranche |
| **Le compte & la clé** | `hasNexusApiKey`, `nexusAccount`, `nexusQuota` | tranche 2 |
| **Le téléchargement** | `isDownloadingFromNexus`, `downloadingNexusModId`, `nexusDownloadProgress`, `nexusDownloadInFlight`, `nexusDownloadQueue`, `nexusDownloadRate`, `nexusArchiveStore`, `nexusArchives` | tranche 3 |
| **Les métadonnées** | `nexusCategories`, `nexusModExtras`, `modDetailState` | tranche 4 |
| **Hors domaine** | navigation (`viewingModDetail`, `pendingModDetailFocus`), installation (`pendingDownloadedZip`, `pendingNexusSource`, `recentNexusInstalls`), plomberie (`updateKeyDeltasRevision`), préférence (`autoCheckNexusUpdates`) | reste |

**Le discriminant qui a servi à l'ordre des tranches** : *où les vues
écrivent*. Elles écrivent 13 fois `viewingModDetail`, 4 fois
`pendingModDetailFocus`, 3 fois `pendingNexusSource` — **toutes dans
navigation et installation, aucune dans les trois premières familles**. Les
domaines 4 et 5 ont payé leur verrou de taille en façades `get`+`set` ;
celui-ci n'en crée aucune, et la ligne brute baisse pour la deuxième fois
d'affilée. Le diagnostic de la tranche 1 du domaine 6 tient, et il se
mesure : c'est l'écriture par la vue qui coûte.

🚩 **Le verrou avait deux détenteurs, et vivait en `guard` au point
d'appel.** La reprise Nexus démarre **dans** `applySmapiResults`, donc avant
que le `group.notify` de `checkNexusUpdates` n'ait fini : le relâchement de
la première passe éteignait le voyant que la seconde venait d'allumer, le
bouton « Vérifier » réapparaissait pendant que Nexus était interrogé page
par page, et un second passage complet pouvait démarrer par-dessus — aux
dépens du quota Nexus là où smapi.io est gratuit. La défense était un
`guard !nexusFallbackInFlight else { return }` qu'il fallait penser à
écrire ; c'est maintenant `endCheck()` qui refuse de relâcher, et l'appelant
n'a plus de décision à prendre. Même forme que la garde `if
errorHistoryLoaded` de la tranche 3 du domaine 2 : **une règle qui cesse
d'être facultative**.

⚠️ **Ce que le store ne voit pas, délibérément : le cache plat.** Il reste
chez `NexusUpdateChecker.shared`, avec la consolidation par pack et la
fusion d'une passe partielle (429, 503) — pièges mesurés, consignés dans
`CLAUDE.md`. L'appelant consolide, juge le snooze, puis remet les deux
moitiés d'un coup ; y réécrire la liste consolidée aplatirait ce que le
cache doit garder à plat. `updateSnoozer` reste donc au ViewModel : c'est
l'**entrée** de la partition, pas la partition, et il lui faut la version du
jeu, qui vient d'un autre domaine.

**Deux tuples deviennent des types.** `unverifiableMods` était
`[(uniqueId:name:blocker:)]`, remappé à la main depuis
`SmapiVerdicts.Unverifiable` — qui a exactement cette forme, est `Equatable`
et vit déjà en Core. `nexusCheckProgress` devient `UpdateCheckProgress` : un
tuple n'est pas `Equatable`, donc la vue ne pouvait animer que `done`.

**Trouvé en chemin, corrigé à part** : `outOfDateMods` n'était pas du Nexus
malgré son voisinage d'affichage — voir le correctif du domaine 2 du même
jour. Leçon de méthode : classer un relevé par **producteur**, jamais par
préfixe de nom.

**Vérification à l'écran — OK, auteur, 2026-09-12.** Les quatre contrôles sont passés, dont celui qui porte : le voyant ne s'éteint pas entre la passe smapi.io et la reprise Nexus. Ce qui a été exercé :
fenêtre des mises à jour :

1. « Vérifier » sur le parc complet — la progression avance, le bouton reste
   indisponible, l'erreur d'une passe précédente a disparu ;
2. **le contrôle qui porte** : quand la passe smapi.io se termine et qu'une
   reprise Nexus enchaîne, le voyant **ne s'éteint pas entre les deux** et le
   bouton ne redevient pas cliquable.
   ⚠️ **Précondition, sans quoi ce contrôle est vide** : une clé d'API Nexus
   doit être configurée — `resumeNexusFallback` sort sur un `guard` **avant**
   d'ouvrir la reprise quand il n'y en a pas, et le voyant se comporterait
   alors « correctement » sans que le verrou ait jamais été sollicité. La
   preuve que la reprise a bien démarré est la ligne de journal
   « Reprise Nexus : N mods sans verdict, M pages à interroger » : sans elle,
   le contrôle n'a pas eu lieu ;
3. les invérifiables que la reprise a tranchés quittent la liste repliée,
   **ceux qu'elle n'a pas atteints y restent** ;
4. mettre une mise à jour en veille — elle quitte la liste et le badge, et
   reparaît sous « en veille » sans que l'inventaire bouge.

### Domaine 7 — Nexus, tranche 2 (le compte et la clé), livrée le 2026-09-12

Un commit (`62bd694` : store **et** câblage — trois propriétés, séparer les
deux n'aurait rien montré de plus), gate exit 0, **3 092 tests verts**.
`NexusAccountStore` (`@Observable`, 7 tests, six sabotages).
`viewmodel_stored_state` 114 → **111** ;
`observable_stored_without_private_set` 99 → **98** ; ViewModel inchangé à
**10 270** — sur trois propriétés, les façades coûtent ce que les
déclarations rendent.

**Trois propriétés, cinq règles.** C'est le rapport qui justifie la tranche :
ce n'est pas la taille de l'état qui décide, c'est ce qu'il tient
implicitement.

1. **Le compte appartient à la clé.** Poser une clé neuve invalide le compte
   connu — ce peut être un autre compte, d'un autre type ; le garder
   afficherait « premium » à qui ne l'est plus.
2. **Retirer la clé emporte compte et quota, et eux seuls.** Les mises à jour
   déjà relevées restent dues : elles ne doivent rien à la clé, qui ne sert
   qu'au téléchargement intégré et aux fiches. Le commentaire le disait ;
   rien ne le tenait.
3. **L'ignorance ne retire rien.** `directDownloadUnavailable` n'est vrai que
   quand on *sait* que le compte n'est pas premium. Le sabotage qui compte
   est `account?.isPremium != true` — la forme qu'on écrit sans y penser,
   et qui cacherait le bouton à qui y a droit tant que Nexus n'a pas répondu.
4. **Le renseignement vieillit** — une semaine, épinglée des deux côtés du
   seuil.
5. **Le lot du lancement** publie les trois d'un coup.

⚠️ **Le Trousseau n'entre pas dans le store.** La clé reste chez
`NexusUpdateChecker.shared` ; le store n'en retient que le **fait** qu'elle a
été acceptée. La nuance est celle d'un défaut déjà corrigé : déclarer la clé
configurée sans que le Trousseau l'ait prise faisait afficher « configurée »
à une UI dont la vérification suivante repartait en `.noApiKey`.

⚠️ **Une redondance laissée en place**, délibérément : `refreshNexusAccount`
garde `guard hasNexusApiKey || NexusUpdateChecker.shared.apiKey()?.isEmpty
== false`. Les deux sources répondent à la même question, mais le lot du
lancement est asynchrone — la seconde couvre l'instant où la clé existe et
où le store ne le sait pas encore. La retirer demanderait de prouver cet
ordre, ce que la tranche ne fait pas.

Aucune vue touchée : les six qui lisent ces valeurs
(`SettingsView`, `ModDetailView`, `DiscoverView`, `ProfileDiagnosticsView`,
`MainView`) ne font que les lire — `disabled`, `help`, `if`.

**Vérification à l'écran — OK, auteur, 2026-09-12.** Les trois contrôles sont passés, dont celui qui porte : retirer la clé n'emporte pas les mises à jour déjà relevées. Ce qui a été exercé :
réglages :

1. coller une clé d'API valide — « configurée » apparaît, le quota se
   remplit, et les boutons de recherche Nexus des fiches de mod
   redeviennent actifs ;
2. **le contrôle qui porte** : retirer la clé — le quota et le compte
   disparaissent avec elle, mais la **liste des mises à jour déjà relevées
   reste** (elle ne doit rien à la clé) ;
3. remplacer une clé par une autre — le bouton « télécharger » ne reste pas
   dans l'état premium de l'ancienne le temps que Nexus réponde.
   ⚠️ **Précondition, sans quoi ce contrôle est vide** : l'ancienne clé doit
   être premium et la neuve gratuite (ou l'inverse). Entre deux clés de même
   type, le bouton a la même apparence avant et après, et le contrôle ne
   discrimine rien. À défaut de deux clés de types différents, s'en tenir
   aux contrôles 1 et 2 — le 2 est celui qui porte.

### Domaine 7 — Nexus, tranche 3 (le téléchargement en vol), livrée le 2026-09-12

Deux commits (`72f4097` store + câblage, `65aabd6` le cliquet), gate exit 0,
**3 100 tests verts**. `NexusDownloadStore` (`@Observable`, 8 tests, cinq
sabotages). ViewModel 10 270 → **10 254** (−16, troisième baisse d'affilée) ;
`viewmodel_stored_state` 111 → **105**.

**La moitié de la famille n'était pas de l'état.** Sur les huit propriétés
relevées, quatre sont des **collaborateurs** — la tâche annulable, la file,
l'estimateur de débit, le magasin d'archives — tous déjà en Core. Le store
les possède (sauf les archives, reportées en tranche 4) ; seules trois sont
publiées.

**L'asymétrie qu'il corrige.** La remise au repos était déjà regroupée dans
`clearNexusDownloadState`, dont le commentaire disait pourquoi : quatre
témoins remis à zéro à trois endroits, et en oublier un condamnait le bouton
pour la session. L'**ouverture** restait posée à la main — sur les deux
seuls sites qui démarrent un transfert, un mod et une traduction. *Deux,
vérifié par grep sur tout le dépôt* : deux mises à `true`, une seule mise à
`false`.

Trois règles épinglées : la barre reste **muette** pendant que le lien se
résout (les deux appels d'API n'ont rien à mesurer, le drapeau porte
l'attente) ; **annuler ne conclut pas** (`URLSession` rapporte l'annulation
par le chemin d'échec, conclure des deux côtés laisserait l'état au repos
pendant qu'un transfert continue) ; **le débit ne survit pas à son
transfert**.

🚩 **Deux tests étaient creux — trouvés par sabotage, pas par relecture.**
Les deux premiers jets passaient avec *et* sans leur mécanisme :

- le **débit**, parce que deux relevés posés dans la même milliseconde ne
  rendent aucun débit : `noteProgress` prend désormais un `now` injectable,
  et le sabotage mesure la survie à 0,5 o/s ;
- la **barre remise à zéro à l'ouverture**, parce qu'un store neuf a déjà
  `progress == nil` : il fallait ouvrir un **second** transfert pour que
  l'attente discrimine.

C'est la troisième fois en une session qu'un test écrit de bonne foi ne
tient rien. Le point commun des trois : **l'état initial du store satisfait
déjà l'attente**, ou la valeur mesurée est indisponible pour une raison
étrangère au mécanisme (ici l'horloge).

🚩 **Le cliquet surcomptait de 44 %** — trouvé parce que les deux `private
var` du store faisaient monter `observable_stored_without_private_set`.
**29 des 95 violations comptées étaient des `private var`**, plus strictes
que `private(set)`. Et le motif ne voyait pas du tout `public private(set)
var` (l'ordre idiomatique Swift) ni `private static var` : 3 membres
échappaient au décompte, tous conformes — le cliquet surcomptait, il ne
laissait rien passer. Base 95 → **66**, et l'outil corrigé a été prouvé
encore capable d'échouer (une stockée exposée : exit 1 ; la même en
`private` : exit 0).

⚠️ Le jugement « suis-je occupé ? » reste au ViewModel : `NexusDownloadFlow`
tranche sur le couple (`isDownloading`, `pendingDownloadedZip`), et la
seconde moitié appartient à l'installation — même forme que l'entrée du
snooze en tranche 1.

⚠️ **Deux surfaces publiques retirées après coup**, dont l'unique
consommateur était leur propre test : `inFlight` est passé `private` (le
lire inviterait à prendre `inFlight != nil` pour un test d'occupation, le
jugement qu'on vient justement de laisser au ViewModel) et
`hasQueuedDownloads` a été supprimé (le test interroge `dequeue()`, ce qui
prouve en plus que la file se vide). Conséquence assumée et écrite dans le
store : la remise à `nil` de `inFlight` n'est couverte par aucun test —
`NexusFileDownload` est `final`, donc pas de doublure ; ce qui la tient est
qu'elle n'a qu'**un** point d'écriture.

**Vérification à l'écran — OK, auteur, 2026-09-12.** Les trois contrôles sont passés, dont celui qui porte : annuler ne remet pas l'état au repos avant que l'annulation ne soit rapportée. Ce qui a été exercé :
de mod ou la liste des mises à jour (clé d'API premium requise pour le
téléchargement direct) :

1. lancer un téléchargement — l'attente d'abord **sans barre** (le lien se
   résout), puis la barre avec volume et débit ;
2. **le contrôle qui porte** : annuler en cours — le bouton ne redevient pas
   cliquable *avant* que l'annulation ne soit rapportée, et l'état ne se
   remet pas au repos pendant que le transfert s'arrête ;
3. lancer un second téléchargement pendant le premier — il est **mis en
   file** (ligne de journal « en attente ») et démarre tout seul quand la
   feuille d'installation du premier se ferme ; son débit repart de zéro et
   n'hérite pas de celui du précédent.

### Domaine 7 — Nexus : clos à trois tranches, le 2026-09-12

Il n'y aura **pas de tranche 4.** Les quatre propriétés qui restaient ont
été examinées et laissées au ViewModel — pour des raisons qui tiennent, et
qu'il valait mieux écrire que de fabriquer un store qui n'épingle rien.

| Ce qui reste | Pourquoi |
| --- | --- |
| `nexusCategories`, `nexusModExtras` | Une décision antérieure les excluait déjà de `NexusMetadataStore` (« miroirs du cache du checker »), et la reconnaissance confirme que la raison tient : la copie qui fait foi vit dans `NexusUpdateChecker`, derrière `withMetadataCacheLock`, et `saveCachedCategories`/`saveCachedExtras` lui sont **privées**. Un store autour de ces deux cartes ne posséderait ni la persistance ni le verrou : il n'épinglerait aucune règle que le checker ne tient déjà. **L'inverse exact de la tranche 2**, où trois propriétés portaient cinq règles découplées. |
| `modDetailState` | Un seul optionnel, un seul lecteur (`ModDetailView`), et les transitions (`initial`, `refreshed`, `stopLoading(ifShowing:)`) vivent déjà dans le type `ModDetailState`. L'extraire n'achèterait qu'une façade. |
| `nexusArchives`, `nexusArchiveStore` | `nexusArchiveStore` est une référence à un magasin **déjà** en Core, et `nexusArchives` n'est qu'un miroir publié de ses `entries()`. Un store d'une propriété ne vaut pas la peine. Seul resserrage réel appliqué : `var` → **`let`** — aucune vue ne remplace la référence, et `var` non privé offrait de le faire. |

🚩 **Une hypothèse de défaut, vérifiée puis abandonnée.** `fetchMetadata`
écrit les deux cartes en mémoire sans rien persister : j'en ai conclu qu'une
catégorie apprise par la recherche à la demande ne survivrait pas au
relancement. C'est faux. `fetchSingleMod`, que cette fonction appelle,
persiste **déjà** catégorie et extra dans le cache partagé, sous le verrou,
avec même une garde contre la clé effacée pendant le vol
(`metadataGeneration`). Le commentaire le dit en toutes lettres. Lire le
chemin du ViewModel sans lire la fonction qu'il appelle m'avait fait voir un
trou là où il n'y en a pas — un correctif écrit sur cette base aurait ajouté
une couture publique inutile et une double persistance.

**Le domaine est clos pour son état.** Ne reste que de l'orchestration
réseau — la composition des deux requêtes (`NexusUpdateCheck`), la reprise
page à page, et la résolution des liens de téléchargement.

### P8 — la reprise des vues, tranche 1 (la règle du changement d'onglet), livrée le 2026-09-12

Un commit (`62f1581`), gate exit 0, **3 111 tests verts**. `TabChangePlan`
(Core pur, 11 tests, six sabotages). MainView 1 570 → **1 554** ;
ViewModel 10 254 → **10 251**.

**Pourquoi P8 avant le domaine 8.** La mesure de composition du ViewModel,
faite le 2026-09-12 : sur ses 10 255 lignes, **38 % sont du commentaire**
(2 380 `///` + 1 582 `//`), 7 % des lignes vides, et 54 % du code effectif —
dont 3 980 lignes dans **344 fonctions** (moyenne 11,6 ; la plus grosse,
`toggleAllMods`, fait 105 lignes). Ce n'est pas un monolithe, c'est un
annuaire. Et le chantier B, qui extrait l'**état**, troque une déclaration
contre une façade à coût nul en lignes : **57 façades d'une ligne coûtent
170 lignes brutes** avec leur documentation, et **38 fonctions sont de purs
relais** d'une seule instruction. D'où le classement des cibles :

| Ce que les vues écrivent | sites |
| --- | --- |
| **navigation** (`viewingModDetail` 13, `editingSave` 10, `editingModConfig` 9, `pendingDetailTab` 6, `viewingSaveTimeline` 6, la famille `pending*Focus`) | ~55 |
| les 5 façades `get`+`set` vers un store (`saveViewMode`, `saveSortOption`, `saveFilterTag`, `lastRepairReport`, `quarantineActionMessage`) | 8 |
| le reste (alertes, focus divers) | ~23 |

**24 propriétés, 86 sites.** La navigation domine, et c'est la seule famille
dont la règle a déjà mordu trois fois.

**Ce que la tranche achète.** `MainView.handleTabChange` portait quarante
lignes de règles hors de portée d'un test. Elles sont maintenant dans
`TabChangePlan`, avec ce qu'un relevé rapide aurait aplati : les trois
intentions n'ont **pas le même sort** (la traduction survit, les deux autres
s'effacent) ; une demande introuvable **emporte l'onglet demandé** (le cas
voisin — une demande qui aboutit le garde — est testé aussi) ; et il y a
**deux parcs**, le déplié pour les intentions par dossier, le premier niveau
pour `ModFocusResolver` qui déplie lui-même. Le sabotage qui unifie les deux
casse l'accès au pack.

⚠️ **Une différence de comportement évitée**, invisible aux 11 tests parce
que la règle est pure : le premier jet affectait `viewingModDetail` et
`editingModConfig` **sans condition**, rejouant leurs `didSet` sur un second
`nil`. Vérifié inerte dans les deux cas (l'un ne fait rien sans valeur,
l'autre est gardé par `oldValue != nil`, écrit pour X66) — la forme
conditionnelle retenue n'a pas besoin qu'ils le restent.

**Vérification à l'écran — OK, auteur, 2026-09-12**, avec un constat de
latence sur le chemin « couverture française d'un profil → fiche », mesuré
et consigné en ROADMAP (voir ci-dessous).

### P8 — tranche 2 (le store de navigation), livrée le 2026-09-12

Trois commits (`2b7ef69`, `fa35521`, `aec7036`), gate exit 0, **3 136 tests
verts**. Plan : `docs/superpowers/plans/2026-09-12-p8-2-store-navigation.md`.
ViewModel **10 251 → 10 247** — la tranche se juge à l'état déplacé, pas aux
lignes : `viewmodel_stored_state` **104 → 89** (−15). `NavigationStore`
(Core, 215 l.), **14 tests** (234 l.).

Les **quinze propriétés** de navigation quittent le VM : les cinq vues de
détail (`viewingModDetail`, `editingModConfig`, `editingSave` +
`inventoryToEdit`, `viewingSaveTimeline`, `viewingThaiMod`), les sept
requêtes (`pendingModFocus`, `pendingTranslationFocus`, `pendingConfigFocus`,
`pendingModDetailFocus`, `pendingDetailTab`, `pendingTranslationDiffFilter`,
`pendingLogFocus`) et les deux canaux pose-consomme (`reportDetailFocus`,
`pendingTabRequest`). Les documentations voyagent avec elles. **Aucune vue
touchée** : façades de mêmes noms, marquées provisoires — la reprise des
vues (tranche P8 suivante, ~55 sites d'écriture) les appellera directement.

**Les décisions :**

- **Setters nommés, pas `didSet`, sur une propriété `@Observable`.** Les
  trois poses à effet (`setViewingModDetail`, `setEditingModConfig`,
  `setEditingSave`) portent la décision ; le dépôt n'a **aucun** exemplaire
  du couple macro Observation + observer, on n'introduit pas l'expérience.
- **L'I/O par closures, câblée par `wireEffects` dans
  `init(localization:)`.** Le plan prévoyait un `lazy var` — le compilateur
  l'a refusé : le VM est lui-même `@Observable`, la macro transforme les
  propriétés stockées en computed et `lazy` y est interdit. Le store garde
  un `init` à paramètres pour les tests (espions), `wireEffects` est la voie
  de l'app. Les closures restent `private(set)` : le câblage ne se refait
  pas en vol.
- **`inventoryToEdit` reste publique en écriture** — déviation du plan (qui
  prévoyait `private(set)`) : `SavesView` lie les `stack` par binding
  sous-indexé (`$vm.inventoryToEdit[index].stack`), et `saveInventory()`
  rafraîchit l'affichage depuis une re-lecture du fichier sans reposer
  `editingSave` — deux écritures sans règle attachée, dans les deux mondes.
- **`DetailTab` et `DiffFilter` descendent en Core** (commit 1) — un store
  Core ne peut pas référencer un type de vue. `DiffFilter` vit dans
  `TranslationDiffFilter.swift`, imbriqué dans son modèle par extension
  cross-fichier : `TranslationCoverage.swift` est verrouillé par le cliquet
  des tailles (patron `ArchivePaths`). Alias dans les vues (patron
  `DiscoveryRow`).

**Ce qui reste au VM, relevé avec raison** : `saveToDuplicate`,
`backupToBranch` (présentation locale, cadrage du domaine 1) ;
`pendingToggleFolder`/`pendingDeleteFolder` (état d'**opération**
bascule/suppression, posé et consommé par le VM lui-même) ;
`alertMessage`/`showAlert` (famille « alertes » du tableau P8) ;
`modDetailState` (décision du domaine 7).

**Douze sabotages posés, six mécanismes rougis** (pose qui déclenche, nil
qui ne déclenche pas, X66 à l'ouverture, X66 à non-nil→non-nil, garde
anti-course retirée, vidage préalable retiré, nil qui ne vide plus) — et
**deux tests creux trouvés en chemin, renforcés** : le vidage préalable
était invisible tant que la closure espion était synchrone (le `done`
écrasait le vieux contenu de toute façon — différencié), et
`fermerLaSauvegardeVideSansCharger` ne portait pas son propre mécanisme
(l'inventaire était déjà vide avant le `nil`). Le cas voisin
(`linventaireFraisAtterrit`) reste vert : un garde trop large serait vu.

⚠️ **Vérification à l'écran — par l'auteur** (condition 4, jamais un agent) :
(1) fiche depuis la liste, retour, autre fiche ; (2) alerte système → fiche
sur l'onglet État après changement d'onglet ; (3) éditeur de config depuis
le rapport de raccourcis, fermeture → rescan (X66) ; (4) éditeur
d'inventaire, deux sauvegardes vite enchaînées — l'affiché est le second
(anti-course) ; (5) timeline de sauvegarde, fiche thaï ; (6) couverture de
profil → « traduis ce mod » → fiche sur l'onglet Traduction ; (7) alerte
sans mod → focus recherche des Journaux ; (8) ⌘1…⌘9 et « voir la fiche » du
bilan ; (9) « Traduire les nouveaux textes » → diff cadré.

### Domaine 8 — Scan & parc, livré le 2026-09-12

Un commit (`6b5de04`), gate exit 0, **3 146 tests verts**. Plan :
`docs/superpowers/plans/2026-09-12-domaine-8-scan-parc.md`. ViewModel
10 247 → **10 236** ; `viewmodel_stored_state` 89 → **82**. `ScanStore`
(Core, 128 l.), **10 tests** (125 l.).

**Le lourd vivait déjà en Core** — c'est ce qui a rendu le dernier domaine
le plus court : le balayage, la lecture des manifestes, le cache mtime et
**son verrou** (`ModScanner`, une classe — deux `scanMods()` concurrents
doivent toucher le même cache, verrouillé dedans, crash de juillet 2026),
`ModsFolderSizer`, `ModDuplicateIndex`, `ScanProgress`. Le store ne porte
que l'état publié (`mods`, `scanProgress`, `duplicateIndex`,
`modsFolderSizes`, `isMeasuringModsFolder`) et le mécanisme de
sérialisation des poids (une passe à la fois, demande rejouée, mesure
ratée qui n'efface pas pendant qu'une passe est en route — règle :2671
passée sous test). `performInitialLoad`/`scanMods`/`parseModFolder`
restent au VM : orchestration disque.

**Les cascades du parc** : poser `mods` **prévient**, sans garde
d'égalité (fidèle au `didSet` Swift, qui ne compare pas) ; les trois
consommateurs (cache de catégories Nexus, couverture française, rapport
de raccourcis) sont câblés en un seul `onModsChanged` dans l'init — la
règle testée est « toute pose prévient », le détail des trois est de
l'app.

**Le N+1ᵉ et le N+2ᵉ chemin, trouvés par le compilateur** : le relevé
annonçait `modsFolderSizes` écrit seulement par la mesure — le câblage en
a fait sortir **deux** autres sites, tous deux la règle « la clé des
poids suit le renommage » (B2-T2) : la bascule (une clé) et le renommage
X60 (**deux** clés physiques — actif et pause). Ils passent par
`renameSizeKey(from:to:)`, verbe documenté du store ; le commentaire
« joindre sur le nom logique rendrait 0 octet pour tout mod en pause »
voyage avec lui.

**Sept mécanismes rougis par sabotage**, deux vagues (la pose identique
non notifiée, la notification jamais émise, l'index avalé, le verrou
retiré, le drapeau jamais consommé, la pose inconditionnelle qui efface,
le nil jamais posé). ⚠️ T1 et T2 du plan sont livrés en **un** commit :
les tests écrits en avance sur la T2 rendaient le découpage artificiel —
le target doit compiler à chaque commit, la CI juge chaque poussée.

**Vérification à l'écran — par l'auteur** : (1) lancement, barre par mod
puis compte final ; (2) la liste affiche le parc ; (3) bascule → poids de
la ligne mis à jour ; (4) pastille d'alertes sans ouvrir l'onglet ;
(5) couverture FR recalculée après un scan ; (6) pied de barre « mesure
en cours » puis poids total ; (7) deux scans rapprochés sans crash.

### P8 — la reprise des vues, tranches 3-5 (les façades sortent), livrées le 2026-09-12

Trois commits (`b2c64633`, `f59c8a50`, `431f29ca`) : les vues écrivent les
stores directement, les façades provisoires sortent du ViewModel.

- **Navigation** (~70 sites, 9 fichiers) : lectures `vm.navigationStore.X`,
  écritures à règle par les setters nommés (`setViewingModDetail`,
  `setEditingModConfig`, `setEditingSave`), affectations simples pour
  `viewingThaiMod`, `viewingSaveTimeline` et `inventoryToEdit`. Le binding
  sous-indexé de `SavesView` (`$…inventoryToEdit[index].stack`) passe par une
  projection `@Bindable` locale — `vm.navigationStore` reste un `let`, un
  chemin de binding doit être écrivable (+4 lignes assumées au cliquet).
- **Scan & entretien** (~68 sites) : `vm.scanStore.mods`/`.scanProgress` ;
  la Quarantaine écrit par `setRepairReport`/`setQuarantineMessage`. `mods`
  reste en façade de **lecture assumée** (cond. 1 assouplie — dizaines
  d'usages internes) ; `scanProgress`, `duplicateIndex` et les deux façades
  maintenance sortent.
- **`pending*`** (30 sites, 7 façades) : `vm.navigationStore.pending*`.
  `pendingNexusSource`/`pendingToggleFolder`/`pendingDeleteFolder` restent de
  l'état du VM — jamais des façades.

Deux rats du sed, corrigés au gate : la **fonction** `vm.mods(matching:)`
(pas la façade) et le nom `quarantineMessage` côté store. Les quatre
écritures internes du VM (reset de `scanMods`, phases de lancement, bascule
X57) passent par `scanStore.setMods`/`.scanProgress`. Marquées provisoires
restantes : **zéro** — les cinq « cond. 1 » suivantes sont des façades de
lecture assumées à demeure. Reste hors périmètre : la famille **alertes**
(`alertMessage`/`showAlert`, état stocké du VM — extraction puis reprise,
une tranche propre). VM : 10 236 → 10 129 lignes.

**Vérification à l'écran — par l'auteur** : (1) fiche mod ouvre et ferme
depuis liste, arbre de dépendances et alertes système ; (2) éditeur de
config ouvre et une écriture rejoue le scan de raccourcis (X66) ; (3)
sauvegardes — édition d'inventaire (quantités), duplication, timeline ; (4)
hub thaï ; (5) Quarantaine — vider vers la corbeille met à jour bannière et
message ; (6) splash — barre par mod puis compte final ; (7) les foci
depuis un autre onglet (Alertes système → config, recherche → fiche).

## Bilan du chantier B — clos le 2026-09-12

Les **huit domaines** sont extraits pour leur état. `viewmodel_stored_state`
est descendu de **128 à 82** — l'écart restant est relevé, nommé, et
pour l'essentiel retenu exprès (les décisions des domaines 2, 7 et du
P8-2 : orchestration réseau, miroirs de caches verrouillés ailleurs,
présentation locale). `viewmodel_facades_to_combine` reste à 0. Le
ViewModel fait **10 236 lignes** contre 11 902 au relevé du 2026-09-10 —
mais la tranche se juge à l'état déplacé et aux règles passées sous test,
pas aux lignes : **23 stores** dans `Stores/`, tous en Core, tous testés.

Ce que le chantier n'a **pas** fait, et qui reste ouvert :
- **P8 — la reprise des vues** : **fait aux trois quarts** le 2026-09-12
  (tranches 3-5, voir ci-dessus) ; reste la famille **alertes**
  (`alertMessage`/`showAlert` — extraction puis reprise) et les cinq façades
  de lecture assumées (cond. 1, à demeure).
- **F3** — **fermée le 2026-09-12** : mesurée par A/B des témoins
  (défaut préexistant), diagnostiquée par capture Instruments (`inferTag`
  relancé par frappe), corrigée (`fd6f0d08` — tag calculé à l'init de
  `ModItem`), vérifiée à l'écran. Voir la case ROADMAP.
- Le **domaine Scan pour ses fonctions** (`parseModFolder` imbriquée,
  REFACTORING §5 point 4) — non extractible au critère des entrées, à
  reprendre au contact.

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

⚠️ **Ce que son `0` dit — et ce qu'il ne dit pas** (mesuré le 2026-09-11, à
refaire avant d'en conclure quoi que ce soit plus tard). Il dit « aucune
**propriété calculée** du VM ne délègue à un objet resté en Combine ». Il ne dit
pas « aucune façade n'existe » : une *méthode* façade échapperait au relevé.
Deux vérifications, hors cliquet, ferment l'écart aujourd'hui — six corps de
fonction citent une de ces instances (`installSmapi`, `toggleAllMods`…), tous
des **verbes**, or le cas 4 ne mord que sur une lecture rendue par un `body` ;
et `localization`, exclu de la liste exprès, est reçu en `@ObservedObject` par
les 45 vues qui traduisent — elles l'observent directement (cas 1), aucune ne
passe par le VM (`vm_dot_L_calls` = 0).

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

## 9. Ce qui est livré — chantier A, 2026-09-11

Onze commits, de `63d1278` à `aac7129`. Gate vert (`python3 build_app.py`,
exit 0), 2 976 tests verts.

| Étape | Ce qui a été fait |
| --- | --- |
| 1 | `keybindReport` rejoint l'état du VM — miroir sur `$report` + `removeDuplicates()`, pas sur `objectWillChange` (qui copiait la valeur **d'avant** l'écriture). `keybindProblemCount` supprimée : zéro appelant. |
| 2 | Les préférences IA locale et DeepL vivent en miroirs synchrones ; lecteurs statiques partagés ; `resyncMirroredDefaults()` pour les écritures faites hors du VM. |
| 3 | `deepLCredentials` reste **calculée** — la mémoïser était une erreur : aucun rendu ne la lit. |
| 4 | **La conversion atomique** : `StarHubTHViewModel`, `GameEnvironmentStore`, `NexusMetadataStore` et `SaveNotesStore` passent `@Observable`. 133 `@Published` retirés, 87 sites de vue passés en propriété nue, `@Bindable` sur les 4 vues qui projetaient, `@State` + `State(initialValue:)` dans l'App. Le relais `objectWillChange` du store Nexus devient une closure injectée. |
| 5 | Trois compteurs de cliquet remplacent `published_without_private_set`. |

### Les défauts trouvés après coup — tous par revue ou par mesure

Aucun n'était visible à la compilation. C'est le point du §5 : le compilateur
ne couvre pas ce chantier.

- **Une perte de données réelle**, antérieure au chantier : `DefaultsMigration`
  ne reprenait pas `"defaultProfileId"`. Sur une installation migrée, le profil
  par défaut était perdu définitivement.
- **Le suivi des memos.** Sous `ObservableObject`, remplir un cache privé
  pendant un rendu était invisible à SwiftUI. Sous `@Observable`, c'est une
  publication. Mesuré sur `withObservationTracking` : deux vues sœurs lisant
  deux clés d'un cache à **créneau unique** bouclent à l'infini ; un
  cache-dictionnaire converge en deux passes. Un `body` ne s'auto-invalide
  jamais — l'observateur n'est armé qu'après la fermeture. Traités :
  `deltaReadCache`, `renamePairsCache`, `_bisection` (hors suivi), et
  `categoryCache` (hors suivi **plus** une révision suivie, parce que le vider
  était son unique signal de rafraîchissement — l'ignorer seul aurait tué
  l'épinglage en silence).
- **Le cliquet lui-même.** La règle des façades rendait 0 en ne décrivant
  aucune propriété : numéros de ligne de la source strippée appliqués à la
  source brute (3 949 lignes d'écart), puis fenêtres avalant les `func`
  intercalées. Corrigée et vérifiée par sabotage. *Un compteur à zéro ressemble
  à un succès* — c'est le troisième outil de contrôle de ce dépôt pris en
  défaut de cette façon.

### Le remède est mesuré, pas seulement le danger

La forme `@ObservationIgnored` + révision suivie + `trackCategoryCache()` a été
exécutée telle qu'elle est livrée (`-O`), trois assertions :

| | Question | Résultat |
| --- | --- | --- |
| 1 | Remplir le cache pour un mod réveille-t-il encore la vue sœur ? | **non** — la tempête de rendu a disparu |
| 2 | Une vue servie par un **succès** de cache est-elle réveillée par l'invalidation ? | **oui** — l'épinglage se rafraîchit toujours |
| 3 | Sabotage : la même sans l'appel à `track()` | **muette** — c'est bien cet appel qui enregistre |

La 2 est celle qui comptait : elle vérifie que `_ = categoryCacheRevision`,
dans une fonction privée, enregistre réellement un accès malgré l'optimiseur.
La 3 interdit de la croire sur parole.

### ⚠️ Un garde-fou perdu au passage

`@Published` émettait à l'exécution le diagnostic *« Publishing changes from
background threads is not allowed »*. `@Observable` **ne l'émet pas**. Or
`scanMods()` peut tourner concurremment avec lui-même (piège connu,
`CLAUDE.md`), et un `manifestCache` sans verrou a déjà causé un
`EXC_BAD_ACCESS` réel. La revue a balayé les blocs
`DispatchQueue.global().async` du VM et n'a trouvé **aucune** écriture directe
à un stocké suivi hors d'un saut par `DispatchQueue.main` — donc rien à
corriger aujourd'hui. Mais le filet qui prévenait est parti : une écriture
hors du fil principal sera désormais silencieuse.

### Compteurs après

| Compteur | Valeur | Ce qu'il verrouille |
| --- | --- | --- |
| `viewmodel_stored_state` | 168 | L'état stocké du VM ne peut que baisser |
| `viewmodel_facades_to_combine` | 0 | Le cas 4 — vérifié par sabotage |
| `observable_stored_without_private_set` | 123 | Remplace `published_without_private_set` |

### La vérification à l'écran — **OK**, auteur, 2026-09-11

C'était le verrou, et il n'était pas formel : le seul angle mort de ce chantier
est « une vue cesse de se rafraîchir sans erreur ni plantage », que ni le gate
ni les tests ne voient, et qu'aucun agent ne peut trancher (convention du
dépôt : aucun agent ne lance l'app). Les contrôles portaient sur les chemins
que la conversion a touchés — pastille d'alertes après un scan de raccourcis,
épinglage/désépinglage de catégorie Nexus, notes et avatars de sauvegarde,
réglages d'IA locale, clé DeepL, bascule de langue, fenêtre de rapport
d'installation.

**Le chantier B est ouvert** (§4).

### Ce qui reste dû, et qui n'est pas une condition

**La mesure F3.** Elle est le critère de succès *de la phase* (§5 bis), pas un
contrôle de conformité du chantier A : le mécanisme peut être correct et le
gain nul. Elle vit dans la ROADMAP comme item à part entière, avec son
protocole A/B propre. Le témoin d'avant la conversion existe — tag
`pre-refactor-observable` sur `e1bb12f`, à bâtir en bundle.
