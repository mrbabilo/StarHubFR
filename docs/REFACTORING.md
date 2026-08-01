# StarHubFR — Plan de refactorisation

> **Statut** : document de travail, versionné (contrairement à `docs/superpowers/`,
> qui est gitignoré). Transposition à nos contraintes du refactor mené en amont par
> `AppleBoiy/StarHubTH` (phases 0-9, achevé le 2026-07-25, donc **postérieur à notre
> fork**). Rattaché à l'**axe F** de `ROADMAP.md`.

## 1. Le problème

`StarHubTHViewModel.swift` concentre profils, scan, Nexus, journal, configurations,
sauvegardes et bissection. Il est passé de 4390 à 4153 lignes le 2026-08-01, ce qui
ne change pas sa nature : c'est un module fourre-tout dont **aucune ligne n'est
testable**.

Le coût est déjà constaté, pas théorique : le 2026-07-31 a produit trois listes de
chemins d'outils divergentes et quatre nettoyeurs de manifeste incompatibles, faute
d'un endroit unique où chaque chose vit.

## 2. La contrainte qui décide de tout

**Ce qui est testable ici, c'est ce qui est inscrit aux `sources:` de `StarHubTHCore`
dans `Package.swift` et n'importe pas SwiftUI.** Rien d'autre. `swift test` ne voit
que ce module ; le ViewModel et les vues n'ont pour filet que la compilation
(`python3 build_app.py`).

Deux sondes ont été passées le 2026-08-01 pour savoir jusqu'où ce module peut aller :

| Sonde | Résultat | Conséquence |
| --- | --- | --- |
| `@MainActor final class … : ObservableObject` dans Core | **compile et se teste** | Un store extrait devient testable — l'extraction n'est pas qu'un rangement |
| `NexusUpdateChecker.swift` (894 lignes, `Foundation` + `Security`) ajouté aux sources | **compile sans modification** | Un fichier sans dépendance SwiftUI rejoint Core par simple déclaration |

**Corollaire méthodologique** : avant d'extraire quoi que ce soit, vérifier si le
fichier n'importe que `Foundation`. Si oui, l'ajouter aux sources coûte une ligne et
rend tout son contenu testable — inutile de déplacer du code.

## 3. Ce qu'on retient de l'upstream, et ce qu'on écarte

**Retenu** — leur découpage en couches, où chaque dossier correspond à une couche,
de sorte qu'une violation se voit dans le chemin du fichier :

```
Models/ (Foundation seul)  →  Services/ (I/O, protocole + implémentation)  →  Stores  →  Vues
```

Retenu aussi : leur ordre d'extraction (le moins enchevêtré d'abord), leur recette
par domaine, et leur exigence d'**un commit par étape numérotée**, pour qu'un
`git bisect` reste trivial.

**Et surtout leur mécanisme de testabilité, qui n'a pas encore d'équivalent ici** :
un protocole par frontière d'I/O (`ModScanning`, `SaveStoring`, `PreferenceStoring`,
`FilePicking`…), une implémentation `Live`, et un **bouchon par protocole** dans
`Tests/Stubs/`. C'est ce qui leur permet de tester un store qui lit le disque ou le
réseau — sans quoi « extraire un store » ne fait que déplacer du code intestable.

Ce mécanisme n'est **pas encore nécessaire** ici, parce que les trois extractions
faites à ce jour portaient sur de la logique **pure** (parseurs, comparaison), qui
se teste sans bouchon. Il le deviendra dès la première extraction touchant au
disque ou au réseau — sauvegardes, registre, Nexus. À ce moment-là : introduire le
protocole **avec** son bouchon dans le même commit, et non « plus tard », faute de
quoi le store arrivera dans Core sans un seul test possible.

**Leurs coordonnées ne sont pas transposables.** Leur ViewModel faisait 2102 lignes,
le nôtre en faisait 4378 au moment de l'audit : tous les numéros de ligne de leur
plan (`4.1 LocalizationStore 380–413`…) sont inutilisables. Ce qui vaut, c'est
l'**ordre** et les **dépendances entre domaines**, pas les emplacements.

**Écarté**, parce que dépendant d'une chaîne de build que nous n'avons pas : XcodeGen
(`project.yml`), les tests `XCUIApplication`, la capture d'écran automatisée, et leur
lanceur de tests maison (nous utilisons swift-testing via SwiftPM).

**Leurs correctifs pendant le refactor valent plus que leur plan.** C'est en les
lisant qu'on a trouvé le bloc de mises à jour SMAPI jamais détecté — bug réel,
présent à l'identique ici, corrigé le 2026-08-01 (`54113eb`).

Deux autres de leurs défauts ont été cherchés chez nous, avec des résultats
opposés — les noter évite de refaire la recherche :

| Leur défaut | Chez nous |
| --- | --- |
| Groupes construits avec `uniqueId: ""` (leur 2.4) : une dépendance à identifiant vide peut se résoudre sur un groupe et passer pour satisfaite | **Présent dans le code** (`StarHubTHViewModel.swift:1207`), mais la chaîne d'exploitation semble coupée : `rebuildDependencyIndexes()` n'indexe que les enfants, jamais le groupe. Ouvert en **F4**, à instruire avant de conclure |
| `customModTags` relu depuis `UserDefaults` à chaque lecture — un décodage de plist par ligne et par redessin (leur 3.5) | **N'existe pas ici.** Cherché explicitement : aucune occurrence. Ce n'est donc **pas** l'explication de la latence de frappe (**F3**), et la piste « rendu » reste non confirmée |

## 4. Méthode

Une extraction se fait dans cet ordre, et chaque étape est un commit :

1. **Chercher la logique pure d'abord.** Un parseur, un calcul, une classification
   enfouis dans le ViewModel ou une vue. C'est là qu'est la valeur : ce code décide
   de ce que voit l'utilisateur, et personne ne le vérifie.
2. **Écrire les tests avant l'extraction**, sur le comportement existant. Un test qui
   n'a jamais été rouge ne prouve rien — le vérifier en cassant volontairement le
   code (fait pour le bloc des mises à jour).
3. **Déplacer sans modifier — sauf à améliorer, et alors le consigner.**
   Swift n'ayant pas d'imports par fichier, un déplacement pur ne peut pas changer
   le comportement : si le build casse, ce n'était pas un déplacement pur.
   **Corriger au passage est autorisé** quand cela répare ou améliore réellement
   le code (arbitrage de l'auteur, 2026-08-01) — à la condition stricte que la
   déviation soit **écrite** : dans la documentation du code *et* au tableau
   ci-dessous. Une amélioration tacite est indiscernable d'une régression
   introduite par mégarde.
4. **Traiter les violations de couche qui bloquent.** Un modèle qui prend le
   ViewModel en paramètre, ou qui porte un `Color`, ne peut pas entrer dans Core.
   Le remplacer par une **clé** ou un **état**, que la vue rend.
5. **Vérifier des deux côtés** : `./run_tests.sh` *et* `python3 build_app.py`.
   Aucun agent ne lance l'application — la vérification visuelle revient à l'auteur.
6. **Poser un repère avant de commencer un domaine.** Un tag
   `pre-refactor-<domaine>` sur le commit de départ : c'est ce qui rend un `git diff`
   de fin d'extraction lisible, et une marche arrière possible sans reconstituer
   l'historique. Repris de leur 0.1, jamais fait ici jusqu'à présent.
7. **Se méfier de l'outillage autant que du code.** Un « build vert » ne vaut que si
   le script échoue vraiment quand il doit échouer. Épreuve passée le 2026-08-01 (les
   deux sortent en 1 : parité de clés rompue, assertion fausse) — **à refaire après
   toute modification de `build_app.py`, `run_tests.sh` ou `release.py`**. C'est là
   qu'étaient les bugs les plus coûteux de l'upstream : voir §8.

## 5. État

### Livré le 2026-08-01

| # | Domaine | Résultat |
| --- | --- | --- |
| 1 | **Journal SMAPI** | `LogEntry` sort du ViewModel (sa présentation `Color` l'en excluait) ; `SmapiLogParser` + le bloc des mises à jour passent en Core avec 13 tests. **Un bug réel corrigé** : les mises à jour signalées par SMAPI n'étaient jamais détectées. |
| 2 | **Catalogue des traductions** | `ThaiTranslationTable` en Core avec 11 tests ; `ThaiTranslationMod` perd ses deux méthodes prenant le ViewModel (une était morte). |
| — | **Comparaison de versions** | `NexusUpdateChecker` rejoint Core sans modification ; 11 tests sur `compare(_:_:)`. Aucun défaut, mais un comportement contraire à l'usage Stardew consigné en A2-T2. |

**F1-T1 est clos.** ViewModel : 4390 → 4153 lignes. 35 tests neufs sur du code qui
n'en avait aucun.

### Prochaines extractions, du moins au plus enchevêtré

**Un seul ordre fait foi : celui de ce tableau.** Le §6 détaille l'intérieur de son
cinquième point (le bloc de tête) et n'ouvre pas une file parallèle — l'ordre qu'il
donne ne s'applique qu'une fois arrivé là.


| Ordre | Cible | Pourquoi |
| --- | --- | --- |
| 1 | `consolidateUpdatesByPack` + `pickHighestVersion` (~78 l.) | Transformations pures ; leur type est déjà en Core. Elles décident quelles mises à jour tu vois — un mauvais regroupement en fait disparaître une. |
| 2 | Registre des mods installés (~298 l.) | Version et date d'installation : de la logique de rapprochement, testable. |
| 3 | Profils (~115 l.) | Petit, mais la bissection s'appuie sur la même machinerie (dépendance croisée signalée dans `ROADMAP.md`) — extraire l'état avant les opérations. |
| 4 | Sauvegardes (~350 l., 4 sections éparpillées) | `SaveManager` est déjà en Core : le gain est surtout de lisibilité. |
| 5 | Le bloc de tête (1934 l.) | Le God module proprement dit — décomposé au §6. |

**Deux chantiers transverses, repris de leurs phases 8 et 9** — absents de la
première version de ce plan :

| Chantier | Quand | Pourquoi ici |
| --- | --- | --- |
| **Découper les vues** (leur P8, cible ~150 lignes) | **Au contact** : quand on extrait un domaine, on découpe la vue qui le consomme, dans le même mouvement | `ModListView` fait 1596 lignes, `MainView` 1125, `SavesView` 794. Une campagne dédiée serait un big-bang sans filet ; couplé à l'extraction, le découpage a une raison d'être et un périmètre |
| **Verrouiller les règles** (leur P9) | **Dès que le premier store existe** | Leur `check_standards.py` empêche la dette de revenir. L'équivalent ici est bon marché : un contrôle dans `build_app.py` refusant qu'un fichier de `Models/` importe SwiftUI — même forme que le contrôle de parité des clés qui existe déjà, et qui sort en `SystemExit(1)` |

**Deux dettes de couche, à traiter au contact plutôt qu'en campagne** — trouvées en
passant leurs correctifs en revue (§8), et sans urgence propre :

| Dette | Déclencheur |
| --- | --- |
| `NSOpenPanel` appelé depuis le ViewModel (`:477`, `:3158`), ce qui rend ces fonctions intestables | **Le premier protocole à écrire** (`FilePicking`), au moment où l'extraction touche l'installation d'un mod ou le choix du dossier de jeu — avec son bouchon dans le même commit |
| AppKit importé hors des vues par `ContrastChecker`, `SaveManager`, `DescriptionBlockParser` et le ViewModel — les trois premiers étant **déjà dans Core** | À traiter quand on modifie l'un d'eux, pas avant : ils compilent, la gêne est théorique tant qu'on n'y touche pas |

**Règle permanente (F1-T2)** : une fonctionnalité neuve ne rentre plus dans le
ViewModel. Elle naît dans son propre type, que le ViewModel se contente d'appeler.
Le plan du hub de traduction la respecte déjà.


## 6. Le bloc de tête — 1934 lignes, 70 propriétés publiées, 36 fonctions

C'est le God module lui-même : tout ce qui précède la première `MARK`. Le décomposer
est le vrai travail ; le reste n'en est que la préparation.

### Domaines qu'on y distingue

| Domaine | Fonctions représentatives | Destination |
| --- | --- | --- |
| **Environnement** | `detectDefaultGameDir`, `selectGameDir`, `fetchSteamUser`, `checkSmapiVersion` | Un type dédié. Le moins enchevêtré : à extraire en premier. `selectGameDir` appelle `NSOpenPanel` → c'est ici que naît `FilePicking` |
| **Localisation** | `L(_:)`, `localizedString(for:)`, `cachedBundle(for:)` | Un type dédié. Techniquement simple, mais `L(_:)` a **des centaines d'appels** : faire le remplacement mécanique dans un commit séparé de l'extraction, sinon le diff devient illisible |
| **Scan** | `scanMods`, `parseModFolder`, `scanEntryForMods`, `cachedManifest`, `migrateDisabledModsToDotPrefix`, `isOsJunk` | Le cœur. `parseModFolder` et `isOsJunk` sont de la **logique pure** : les extraire et les tester **avant** de toucher au reste |
| **Dépendances** | `rebuildDependencyIndexes`, `getMissingDependencies`, `getDisabledDependencies`, `dependencyTree`, `slot(matching:)` | S'appuie déjà sur `DependencyTreeBuilder` (Core, testé). Surtout des index à déplacer |
| **Bascule des mods** | `toggleMod`, `processNextToggleIfNeeded`, `performToggle` | Manipule le disque et sérialise les opérations. À extraire **après** le scan, dont il dépend |
| **Détail de mod** | `loadModDetail`, `fetchModDetailRemote`, `markDetailNotLoading` | Réseau Nexus ; rejoint le domaine Nexus déjà identifié |

### Les 70 propriétés publiées sont le vrai sujet

Elles sont de deux natures que le fichier ne distingue pas :

- **État de domaine** (`mods`, `smapiDiagnostics`, `outOfDateMods`…) : il appartient au
  futur store.
- **État de présentation** (`viewingModDetail`, `editingModConfig`, `showAlert`,
  `selectedModID`…) : il appartient à la **vue qui le possède**, en `@State` — c'est la
  règle 5.3 de l'upstream.

Le tri n'est pas cosmétique : chaque `@Published` du ViewModel publie à **toute** la
fenêtre, `MainView` l'observant en entier. C'est le mécanisme qu'a montré B1-T2 —
sortir le cadrage de la liste dans `ModListState` a restauré la portée d'origine.

**Règle** : à chaque domaine extrait, classer ses `@Published`. Ceux de présentation
ne suivent pas dans le store ; ils redescendent dans la vue.

### Cible

L'upstream a **supprimé** son ViewModel (leur 4.9 : « s'il reste quelque chose, c'est
qu'il n'a pas été classé »). Ce n'est pas l'objectif ici : sans filet de test sur
l'UI, viser la suppression pousserait au big-bang que le §7 exclut.

La cible est **fonctionnelle, pas numérique** : plus aucune logique métier dans le
ViewModel, qui ne garde que la composition — instancier les stores et les relier aux
vues. Le nombre de lignes en découlera ; le viser directement ferait déplacer du code
pour le plaisir du compteur.

### Ordre

Environnement → Localisation → *(logique pure du scan)* → Scan → Dépendances →
Bascule → Détail de mod. Chaque étape est un commit, précédée de ses tests quand la
cible est du calcul pur.

**Cet ordre est interne au §5.5** : on n'y entre qu'après avoir traité les points 1 à 4
du tableau des extractions. Le dire, parce que « l'environnement est le moins
enchevêtré » se lit sinon comme « commencer par lui ».

### Quand un domaine est-il extrait ?

Quatre conditions, toutes vérifiables. Sans elles, « extrait » veut seulement dire
« déplacé », ce qui ne vaut pas le risque pris :

1. **Plus aucune de ses fonctions dans le ViewModel** — pas même une façade qui
   délègue, sauf si des vues non encore migrées l'appellent, auquel cas la façade est
   marquée comme provisoire dans le code.
2. **Ses `@Published` sont classés** : l'état de domaine est parti dans le type extrait,
   l'état de présentation est redescendu en `@State` dans la vue qui le possède (§6).
3. **Sa logique pure est testée** — pas son câblage, sa logique. Si l'extraction n'a
   produit aucun test, c'est que le domaine n'en contenait pas : le noter dans le
   message de commit plutôt que de laisser croire à un oubli.
4. **Les deux gates passent** (`./run_tests.sh`, `python3 build_app.py`) et l'auteur a
   exercé la fonctionnalité à la main — aucun agent ne lance l'application.

### Déviations assumées

Tout écart au « déplacer sans modifier », par extraction. Le tableau existe parce
qu'une de ces trois lignes avait été appliquée sans être dite.

| Extraction | Déviation | Pourquoi, et portée |
| --- | --- | --- |
| Regroupement Nexus (`d802b62`) | `precondition(!updates.isEmpty)` → retour optionnel | Retire un point de crash. L'invariance tenait — les listes viennent d'un regroupement — mais l'exprimer vaut mieux que compter dessus. Aucun appelant affecté |
| Registre des mods (`4d50349`, consigné après coup par `838e32c`) | `Date()` évalué à chaque enregistrement → un instant unique pour tout le lot | Rend la logique vérifiable (l'horloge devient un paramètre) et donne un lot cohérent. Écart réel de quelques microsecondes entre mods d'un même scan ; sans portée, cette date se comparant à une date de mise en ligne dont la granularité est l'heure |
| Arbre des sauvegardes (`4204c6e`) | Filtre par étiquette appliqué **après** le tri, au lieu d'avant | Conséquence de l'extraction : `SaveTree.build` trie en construisant. Résultat identique — un filtre ne réordonne pas ce qu'il conserve |

### Travail concurrent

Ce dépôt est travaillé par plusieurs sessions et plusieurs modèles. Une extraction
touche `StarHubTHViewModel.swift`, c'est-à-dire le fichier que **toute** autre session
risque de modifier. Deux précautions : annoncer le domaine en cours avant de commencer,
et préférer plusieurs petits commits poussés vite à une grosse extraction gardée
locale — un conflit sur 80 lignes se règle, sur 800 il se subit.

## 7. Ce que ce plan ne fait pas

- **Pas de big-bang.** La roadmap l'exclut explicitement : sans filet de test sur
  l'UI, un refactor massif ne se vérifie pas.
- **Pas de renommage de masse.** Leur phase 6 (balayage de nommage) touche des
  centaines d'appels pour un gain cosmétique ; sans revue automatisée, le rapport
  risque/valeur est mauvais ici.
- **Pas de conversion à la concurrence structurée** (leur phase 5) tant que les
  domaines ne sont pas séparés : `@MainActor` sur un fourre-tout de 4000 lignes
  révélerait des dizaines de problèmes réels d'un coup, sans moyen de les isoler.

## 8. Leurs correctifs pendant le refactor, passés en revue

Une vingtaine de commits `fix:` entre le 2026-07-24 et le 2026-07-27. Le tri
complet est ci-dessous pour que personne ne le refasse. **La majorité est sans
objet** : elle porte sur leur chaîne de build (CI, Xcode 16.2, `XCUIApplication`,
capture d'écran, `App Sandbox`), que nous n'avons pas.

Ce qui nous concernait :

| Leur correctif | Vérification ici | Résultat |
| --- | --- | --- |
| Le bloc de mises à jour SMAPI ne détectait jamais rien (une ligne vide le refermait) | reproduit sur un journal de test, en cassant volontairement la correction | **Présent à l'identique. Corrigé** le 2026-08-01 (`54113eb`) |
| `build_app.py` imprimait `[ERROR]` puis sortait en **0** sur échec de compilation ; leur `run_tests.py` ignorait le code de sortie du binaire de test | épreuve empirique : parité de clés cassée volontairement, puis test délibérément faux | **Sain ici.** `build_app.py` → code 1 ; `run_tests.sh` (`set -euo pipefail` + `swift test`) → code 1 |
| `NSOpenPanel` dans le ViewModel rend ses fonctions intestables (leur 3.4) | `grep` | **Présent** : deux occurrences (`StarHubTHViewModel.swift:477` et `:3158`). Ce sera le premier besoin de protocole (`FilePicking`) — voir §3 |
| AppKit confiné à un seul fichier non-vue (leur B.2) | `grep` sur les imports | **Non respecté** : `ContrastChecker`, `SaveManager`, `DescriptionBlockParser` et le ViewModel importent Cocoa/AppKit. Les trois premiers sont **déjà dans Core**, où ils compilent — mais c'est une violation de couche à traiter quand on y touchera |
| `bump_version.py` écrivait `Info.plist` avant de valider le CHANGELOG, laissant un état incohérent | lecture de notre flux | **Sans objet** : nous n'avons pas ce script. `release.py` se contente de **lire** `Info.plist`. Le risque n'existe que si un humain bumpe la version sans toucher au CHANGELOG — l'ordre inverse (CHANGELOG d'abord) reste la bonne pratique |
| `CFBundleVersion` figé à 1 depuis la v1.0.0 | lecture d'`Info.plist` | **Sans objet** : incrémenté à chaque release (8 au 2026-08-01) |

Instruits en second passage, après avoir été écartés à tort sur la seule foi de leur
titre — aucun ne s'applique, mais l'un a fait apparaître l'angle mort ci-dessus :

| Leur correctif | Chez nous |
| --- | --- |
| Tests d'intégration qui se sautaient à chaque exécution : `UserDefaults(suiteName:)` rend **nil** quand le nom de suite égale le bundle ID du processus appelant | **Non concernés** : aucune occurrence de `suiteName`. Le piège reste bon à connaître — notre bundle ID est resté `com.appleboiy.StarHubTH` |
| Capture non-`Sendable` dans `continuation.onTermination` de leur surveillance du journal, erreur dure en mode Swift 6 | **Forme différente** : notre surveillance est un `Timer.scheduledTimer` (`BisectionRunner.swift:155`), pas un `AsyncStream` + `DispatchSource`. Mais **nous ne compilons pas en concurrence stricte**, donc l'équivalent chez nous serait invisible — voir P5 au §9 |

**Ce que ce passage en revue apprend, au-delà des correctifs** : leurs bugs les plus
coûteux n'étaient pas dans le code refactoré mais dans **l'outillage qui prétendait
le vérifier** — un script qui sort 0 sur un échec, des tests d'intégration qui se
sautaient silencieusement à chaque exécution. Vérifier que l'outillage échoue bien
quand il doit échouer vaut autant que vérifier le code.

## 9. Leur plan est-il transposable ? — phase par phase

Verdict : **oui pour sept phases sur dix**, mais jamais telle quelle — leurs
coordonnées et leur outillage ne se transposent pas (§3).

| Leur phase | Transposable ? | Chez nous |
| --- | --- | --- |
| **P0 Garde-fous** | **Oui, et déjà fait pour l'essentiel** | Leur 0.3 — « extraire la logique pure en fonctions libres, la tester, *puis* refactorer autour » — est exactement la méthode du §4, appliquée trois fois le 2026-08-01. **Manquent** : un tag `pre-refactor-baseline`, et le compteur d'avertissements de concurrence (`-Xfrontend -warn-concurrency` dans `build_app.py`) qui sert de jalon à leur P5 |
| **P1 Sortir les types des fichiers fourre-tout** | Oui, mécanique | Fait pour `LogEntry`, `ThaiTranslationMod`, `ModUpdateInfo`. **Mais leur table `current → target` vise une arborescence que nous n'avons pas** — voir la question ouverte ci-dessous |
| **P2 Corriger les violations de couche** | Oui, partiellement fait | `LogLevel.color` et les méthodes de `ThaiTranslationMod` prenant le ViewModel : faits. **Restent** : `Mod.Kind` (qui supprimerait les `flatMap { isGroup ? children : [self] }` réécrits trois fois), les identifiants typés (`Mod.ID` / `NexusID` / `FolderName`), et le `uniqueId` vide des groupes (**F4**) |
| **P3 Protocoles et injection** | Oui — **plus urgent chez nous** | Ils comptaient 26 accès directs à `UserDefaults` ; nous en avons **33** dans le seul ViewModel. `NSOpenPanel` y est appelé deux fois. Pas besoin de leur `DependencyContainer` : un protocole ici, c'est un fichier de plus dans `Package.swift` |
| **P4 Découper le ViewModel** | Oui — c'est le §6 | Leur ordre vaut, leurs numéros de ligne non |
| **P5 Concurrence structurée** | **Douteux — et angle mort** | Ni `build_app.py` ni `Package.swift` ne passent `-swift-version 6` ou `-strict-concurrency` : **nous ne savons pas combien de problèmes existent**, faute de les avoir jamais fait compter (leur 0.4 sert à ça). À ne pas ouvrir avant que les domaines soient séparés — `@MainActor` sur un fourre-tout de 4000 lignes en révélerait des dizaines d'un coup, sans moyen de les isoler. **Première étape, peu coûteuse : mesurer** en ajoutant l'avertissement, sans rien corriger |
| **P6 Balayage de nommage** | **Non** | Des centaines d'appels touchés pour un gain cosmétique, sans revue automatisée. Écarté (§7) |
| **P7 Erreurs typées** | Oui | **Swift 6.3.3** ici : `throws(E)` est disponible. Ce qui les a mordus (une CI sur Xcode 15.4) ne nous concerne pas |
| **P8 Découpage des vues** | Oui — **et ça manquait à ce plan** | Ils visent ~150 lignes par vue. Chez nous : `ModListView` **1596**, `MainView` **1125**, `SavesView` 794, `LogsView` 684, `ModDetailView` 683. À traiter au contact, en même temps que le domaine correspondant |
| **P9 Verrouiller** | Oui — **et ça manquait aussi** | Leur `check_standards.py` empêche la dette de revenir. L'équivalent ici est bon marché : un contrôle dans `build_app.py` refusant qu'un fichier de `Models/` importe SwiftUI, sur le modèle du contrôle de parité des clés qui existe déjà |

### Arborescence — tranché le 2026-08-01 : un dossier `Stores/`

**Décision** : les stores extraits vont dans `StarHubTH/Stores/`, à côté de `Models/`
et `Views/`. Additif, aucun déplacement, `build_app.py` compile déjà `StarHubTH/`
récursivement. Réversible : adopter leur arborescence complète plus tard reste
possible si `Stores/` devient illisible.

**Pourquoi pas leur arborescence tout de suite** : leur meilleure idée — rendre une
violation de couche visible dans le chemin du fichier — est déjà obtenue autrement ici,
et plus solidement. Ce qui est dans `StarHubTHCore` ne peut pas importer SwiftUI, et
c'est le **compilateur** qui le vérifie, pas une convention de nommage. Déplacer des
dizaines de fichiers pour gagner une convention plus faible que la contrainte existante
serait un mauvais échange.

Le détail de leur découpage, pour mémoire — Leur arborescence est `App/`, `Features/<Domaine>/`, `Services/<Domaine>/`, `Models/`,
`DesignSystem/`, `Localization/`, `Support/`. Nous avons `Models/`, `Views/`, et la
racine. **Ce plan ne tranche pas** où vivront les stores extraits au §6.

Deux voies, à choisir une fois pour toutes plutôt qu'au coup par coup :

1. **Adopter leur arborescence.** Une violation de couche devient visible dans le
   chemin du fichier, ce qui est leur meilleure idée. Coût : `build_app.py` compile
   déjà tout `StarHubTH/` récursivement, donc **aucun changement de build** — mais
   beaucoup de fichiers déplacés en une fois, et des commits de déplacement pur qui
   brouillent l'historique récent.
2. **Un seul dossier `Stores/`** à côté de `Models/` et `Views/`, sans toucher au
   reste. Moins expressif, mais additif et sans déplacement.

*(C'est la voie 2 qui a été retenue, cf. la décision ci-dessus.)*
