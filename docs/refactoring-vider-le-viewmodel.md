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

Et deux gardes, vérifiés en compilant :

- `@ObservedObject` sur un type `@Observable` → **erreur de compilation**
  (« requires that 'X' conform to 'ObservableObject' »).
- `objectWillChange.send()` dans un type `@Observable` → **erreur de
  compilation** (« cannot find 'objectWillChange' in scope »).

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
| `@Published` (128 au VM, 23 ailleurs) | 151 | — (à retirer) |
| Classes `ObservableObject` | 8 | — (à convertir) |
| `@ObservedObject` dans les vues | 184 | **oui** |
| `@StateObject` (les deux de l'App) | 2 | **oui** |
| `objectWillChange.send()` | 6 | **oui** |
| Bindings `$vm.…` (à passer en `@Bindable`) | 5 | **oui** |

Les 184 `@ObservedObject` se répartissent en : 87 `StarHubTHViewModel`,
85 `LocalizationStore`, 4 `ModListState`, 4 `KeybindScanService`,
2 `SmapiInstaller`, 2 `BisectionRunner`.

### Pourquoi c'est atomique, et pas séquençable

Le **cas 4** l'impose : un `@Observable` qui lit un `ObservableObject` perd le
suivi **sans le moindre signal** — ça compile, ça s'exécute, la vue ne se
rafraîchit simplement plus. Convertir domaine par domaine créerait exactement
ces chaînes mixtes, et le défaut ne se verrait qu'à l'écran.

Les **huit** classes passent donc ensemble : `StarHubTHViewModel`,
`GameEnvironmentStore`, `LocalizationStore`, `NexusMetadataStore`,
`ModListState`, `SmapiInstaller`, `KeybindScanService`, `BisectionRunner`.

C'est un big-bang, ce que le §7 de `REFACTORING.md` écarte en général. L'écart
est assumé ici pour une raison précise : **le risque d'un big-bang est
proportionnel à ce que le compilateur ne voit pas**, et ici il voit tout sauf
deux choses, toutes deux énumérables (ci-dessous). Le gate compile 294 fichiers
en un module : une chaîne mixte résiduelle est impossible dès lors qu'aucun
`ObservableObject` ne subsiste.

### Les deux angles morts, nommément

1. **Les chaînes mixtes** — éliminées par construction si les huit conversions
   sont dans le même commit. Verrouillé ensuite par un compteur de cliquet à
   zéro (§5).
2. **Les façades lisant une source non observable** (cas 6). Un seul cas connu
   dans le dépôt : `SaveNotesStore.shared`, lu par `savesHierarchy`,
   `availableFilterTags` et `getNote(for:)`, et republié à la main par
   `setAvatar` (`StarHubTHViewModel.swift:7195`), `setNote` (`:7335`) et deux
   sites de vue (`SavesView.swift:926`, `:958`). Sous `@Observable`, ces quatre
   `objectWillChange.send()` **cessent de compiler** — c'est le garde — mais les
   retirer sans rendre `SaveNotesStore` observable ferait cesser le
   rafraîchissement des notes et avatars. `SaveNotesStore` rejoint donc la liste
   des conversions.

⚠️ **Ce recensement est statique.** Il liste les sites qui *appellent*
`objectWillChange.send()` ; il ne prouve pas qu'il n'existe aucune autre vue
dont le rafraîchissement dépendait d'une invalidation globale. Ces cas-là ne se
constatent qu'à l'écran, et c'est ce que la condition 4 doit chercher en
priorité sur ce chantier.

### Ordre des opérations

Le chantier se fait dans cet ordre, parce que chaque étape rend la suivante
vérifiable par compilation :

1. Convertir les **huit** classes (`@Observable`, retrait des `@Published`,
   `final`), plus `SaveNotesStore`. Le build casse — c'est voulu, et la liste
   des erreurs **est** la liste de travail.
2. Reprendre les 184 `@ObservedObject` → propriété simple, les 2 `@StateObject`
   → `@State`, les 5 bindings → `@Bindable`.
3. Supprimer les deux relais `objectWillChange` (`:1982`, `:1988`) et les
   `AnyCancellable` qui les portent : le cas 1 les rend inutiles.
4. Traiter les quatre rafraîchissements manuels restants.
5. Les deux gates, puis la vérification à l'écran.

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
| 1 | **Sauvegardes** (`saves`, `isSaveOperationRunning`, les trois préférences de vue) | ~560 l., `SaveManager`/`SaveTree` déjà en Core, l'état n'est lu que par `SavesView` et ses sous-vues. Et `SaveNotesStore` aura été rendu observable en A : le domaine arrive nettoyé |
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
| `observableobject_remaining` | 8 → 0 après A | Qu'une chaîne mixte réapparaisse (cas 4) — le seul angle mort silencieux |
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

**Tests** : chaque store extrait est inscrit aux `sources:` de `StarHubTHCore`
et testé sur sa logique, pas son câblage — preuve rouge par sabotage (§4.2).
Un store qui n'apporte aucun test le dit dans son message de commit.

**Condition 4** : l'exercice manuel est dû à chaque tranche, et sur ce chantier
il a une cible précise — **chercher ce qui ne se rafraîchit plus**, pas ce qui
plante. C'est le profil de défaut que `@Observable` introduit.

## 6. Ce qu'on écarte, et pourquoi

**Le patron de l'amont (`@EnvironmentObject`)** — ils ont livré 8 stores + un
`AppCoordinator` qui ne publie rien, injectés en un point et déclarés par
111 `@EnvironmentObject`. Écarté pour deux raisons mesurées : leur choix était
**contraint** (ils ciblent macOS 13, `project.yml` et `Info.plist` — `@Observable`
ne leur était pas disponible), et `@EnvironmentObject` plante à l'exécution, pas
à la compilation, alors que nous avons **deux scènes `Window`**
(`StarHubTHApp.swift:132` et `:232`) dont l'une n'hérite pas de l'environnement
de l'autre. Aucun agent ne lance l'application ici : un défaut que seul l'auteur
peut voir est le plus cher du dépôt.

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
| Une vue cesse de se rafraîchir sans erreur ni plantage | Le seul angle mort réel. Contenu par : zéro `ObservableObject` restant (cliquet), les quatre sites connus traités, et une condition 4 ciblée sur le rafraîchissement |
| Le chantier A casse le build longtemps | Assumé : la liste des erreurs de compilation **est** la liste de travail, et le gate est incrémental (~30 s quand une signature bouge) |
| `@Observable` se comporte autrement dans SwiftUI que dans `withObservationTracking` | Non prouvé par le spike. C'est la première chose que la vérification à l'écran doit constater, sur un seul écran, **avant** de convertir les 184 sites |
| Le chantier B s'enlise comme les tranches 15-21 (−20 lignes pour cinq tranches) | Le critère de succès de B n'est pas le nombre de lignes mais `viewmodel_published`, qui ne peut que baisser |

## 8. Découpage — ce que ce document ne fait pas

Le plan d'exécution (tâches, tests, ordre des commits) n'est pas ici. Il sera
écrit séparément, et il commence par une tâche qui n'est pas une conversion :
**convertir un seul écran et le vérifier à l'écran**, pour lever le dernier
risque du §7 avant d'engager les 184 sites.

Deux conventions du dépôt s'appliquent à l'ouverture du chantier : un tag
`pre-refactor-observable` sur le commit de départ (§4.6 de `REFACTORING.md` —
c'est ce qui rend le `git diff` final lisible et la marche arrière possible),
et un commit par étape.
