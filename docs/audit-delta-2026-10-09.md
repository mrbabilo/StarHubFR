# Audit du delta du 2026-10-01 au 2026-10-09

Passe du prompt `docs/prompt-audit.md`, phases 1 à 5, limitée à ce qui a
changé depuis le 2026-10-01 (`dfb8fce4..`) — et, pour les phases 2 et 3,
depuis leur dernier audit du 2026-09-07 (`c0b54852..`). Le reste du dépôt a
été audité en septembre (tranches ①–④ du ViewModel, phases 1 à 5 :
`docs/audit-phase*-2026-09-0*.md`). Ce document ne pose aucun correctif : il
dit lesquels poser.

**Profondeur de lecture — à ne pas surestimer à la prochaine passe :**

| Zone | Lu ligne à ligne | Balayé par motifs seulement |
|---|---|---|
| ViewModel | tout le delta | — |
| `Stores/` | les 11 créés + les diffs des 8 modifiés | — |
| `Models/` | écrivains disque, constructeurs réseau, parseurs neufs, `ActivationHistory`, `ContentPatcherLoadTargets`, `ModImpactHistory`, `ModlistReport`, `ModListSelection`, `ModDetailRefresh`, découverte de `SloDiagnosticContract` (liste en Phase 1 › Models) | présentation `Probe*`, `Keybind*`, `SloDiagnosticLog`/`Report`/`Sources` |
| `Views/` | `MainView` (feuilles), `ProbeOptionsSection`, `BulkConflictGate`, sections Performances citées | le reste des 137 fichiers |
| Réseau | tout le delta : `SmapiBlacklist`, `NexusFileManifestFetcher`, `SmapiInstaller` (lecture du tube), `NexusEndorsementStore`, `NexusModStatsRefresher`, diffs de `NexusUpdateChecker`, `NexusSearchClient`, `DeepLClient`, `NexusDownloadAPI`, `PathoschildCompatibilityList`, `SmapiUpdateClient`, `NexusDownloadStore` | — |
| Persistance | `NexusArchiveStore`, écritures de `ModUpdateKeyDeltaStore` et `NexusPageStateStore`, diff `SaveManager` | autres diffs |
| Sonde C# | — | delta entier ; ni compilée ni testée (`dotnet` hors gate) |
| Build | diffs de `build_app.py`, `release.py`, `check_sources.py` | — |

**Preuves** : X123 démontré **par exécution** (binaire jetable hors dépôt,
compilé sur `NexusArchiveStore.swift`) ; X120, X121, X122, X124 démontrés par
lecture, preuve décrite non exécutée.

**Bilan : 0 🔴, 5 🟡 (X120–X124), 9 durcissements conseillés non numérotés,
une quarantaine de pistes écartées avec leur raison.**

## Corrections à effectuer

Ordre conseillé : du plus visible au plus rare. Chacune est détaillée plus
bas, avec son scénario.

| # | Où | Défaut | Correctif | Preuve à poser |
|---|---|---|---|---|
| X122 | `Stores/ModImpactStore.swift`, `Views/Performance/PerformanceView.swift` | Impact par mod jamais chargé depuis Performances ; état actif/en pause figé jusqu'à la fermeture du jeu | Garder le dernier `ModImpactHistory` ; re-dériver `entries` et les tables quand `mods` change, sans relire le disque ; `reloadIfIdle` dans `PerformanceView.task` | Test Core dans `ModImpactStoreTests` (le store est dans `Package.swift`, `files` et `historyURL` injectables) : `reload` sur un historique temporaire, bascule d'un mod, les entrées suivent `isEnabled` — rouge aujourd'hui |
| X120 | `Views/MainView.swift:422` | Fausse alerte « dépendance absente » sur une archive sans rapport | `vm.clearPendingDependencyExpectation()` sous `vm.pendingNexusSource = nil` | Vérification à l'écran (vue) : dépendance téléchargée, feuille fermée, archive conservée réinstallée — aucune bannière |
| X121 | `StarHubTHViewModel.checkUpdatesViaNexus()` | Vérification bloquée « en cours » si la clé disparaît pendant le tri | Garde de clé Trousseau dans le `guard` de la `Task`, sortie par `updateStore.endFallback()` | Build ; scénario à l'écran (effacer la clé pendant le tri) |
| X123 | `Models/NexusArchiveStore.swift` | Index illisible relu comme vide : la prochaine archive gardée réécrit l'index avec elle seule, les autres deviennent des fichiers orphelins que ni la rétention ni le compteur de stockage ne voient | `loadIndex` rend aussi « lisible ? » ; sur un index présent mais illisible, `keep`/`remove`/`applyRetention` refusent d'écrire et l'index est mis de côté (patron `ActivationHistoryStore.load`, X76) **Exécuté** : 2 archives, index corrompu, `keep` d'une 3ᵉ → `entries().count == 1`, 3 fichiers dans `files/`, `applyRetention()` en efface 0. À reprendre en test dans `NexusArchiveStoreTests` |
| X124 | `release.py` | Ses sorties d'échec rendent 0 (quatre `return`, plus l'envoi refusé qui se contente d'afficher) | `create_release()` rend un code, `sys.exit(create_release())` ; chaque sortie d'erreur rend 1 | **Lecture seule** — ne jamais lancer `release.py` pour le vérifier : il incrémente le compteur et lance `build_app.py` avant tout contrôle |


## Durcissements conseillés (non numérotés)

Aucun ne répond à un défaut observé sur le parc ou par un test : ce sont
des correctifs bon marché qui ferment un cas latent. À poser au prochain
passage dans le fichier, pas en priorité.

| Où | Cas latent | Durcissement | Mesure qui le classe ici |
|---|---|---|---|
| `Models/ModlistReport.swift` (`html`) | Noms, versions et raisons insérés sans échappement HTML : un `<` dans un nom de mod casserait le tableau exporté | Échapper `& < > "` dans chaque cellule | 18 noms du parc portent `&` (toléré par les navigateurs), 0 portent `<` ou `>` |
| `Models/ModlistReport.swift` (`compact`) | Un `\|` dans un nom couperait la ligne du tableau Markdown | Échapper `\|` en `\\|` | 0 nom du parc |
| `Models/HiddenCodeDependencies.swift`, `DotNetMetadata.MetadataFile.init` | DLL corrompue annonçant des milliards de lignes : boucle quasi sans fin en tâche de fond, jamais mise en cache | Refuser des tables dont la taille totale dépasse le stream `#~` | 523 DLL du parc lues en ~10 s |
| `Models/MissingDependencies.swift` (`searchPage`) | `&`, `+`, `=` laissés par `.urlQueryAllowed` coupent la recherche Nexus | Retirer `&+=` de l'ensemble autorisé | Repli de dernier recours, aucun cas mesuré |
| `Views/Performance/PerformanceEnvironmentSection.swift:183` | Deux packs illisibles au même nom affiché : une ligne en double disparaît | Identifier par `folderName` | Liste repliée, visuel |
| `Stores/ModImpactStore.swift` + clé `perf_impact_unreadable` | Historique illisible : la fonction reste éteinte, le message nomme le fichier mais ne mène nulle part (règle « un écran de diagnostic doit conduire ») | Bouton « Afficher dans le Finder », ou mise de côté comme `ActivationHistoryStore` | Écritures atomiques ; jamais observé |
| `SmapiInstaller.swift` (lecture du tube) | Installateur muet et bloqué : la borne de durée n'est relue qu'à l'arrivée d'octets | Lecture par `readabilityHandler` + minuterie, ou délai global sur le processus | Le cas mesuré est l'inverse (6 Mo/s) |
| `NexusUpdateChecker.swift:83,114`, ViewModel L.4940, 5463, 5937 | Cinq clés `UserDefaults` hors `UDKey` (AGENTS §4.3) | Les déplacer dans `UDKey` | Toutes couvertes par `DefaultsMigration` : rien de perdu |
| `companion/StarHubFR.Probe/TextureMemory.cs` | Dictionnaires statiques sans verrou si un mod charge des assets en parallèle | `lock` autour des trois accès | Préchauffage SpaceCore désactivé sur le parc |

## Fichiers porteurs d'un constat

### 📁 `StarHubTH/Views/MainView.swift`
- 🟡 [L.422] X120 — `onDismiss` de la feuille de téléchargement n'efface pas
  l'attente de dépendances.
- Appelle : `vm.pendingNexusSource`, `vm.drainQueuedNexusDownloads()` ;
  impact : faux avertissement dans `InstallPreview`.

### 📁 `StarHubTH/StarHubTHViewModel.swift`
- 🟡 `checkUpdatesViaNexus()` / `recheckBlockedViaNexus(_:)` — X121.
- Détail et pistes : Phase 1 › ViewModel.

### 📁 `StarHubTH/Stores/ModImpactStore.swift`
- 🟡 `reload`/`reloadIfIdle` — X122 (premier chargement absent de
  Performances, `isEnabled` figé).
- Lu par : `ModListRow`, `ModImpactSection`, `PerformanceImpactSection`,
  `PerformanceTextureSection`, filtre impact.

### 📁 `StarHubTH/Models/NexusArchiveStore.swift`
- 🟡 [L.215-218] X123 — index illisible relu comme vide puis réécrit.
- Lu par : `reinstallFromArchive`, carte de stockage, rétention.

### 📁 `release.py`
- 🟡 X124 — code de sortie 0 sur échec.

## Écarts de mesure du prompt

Relevé du 2026-10-03 contre le dépôt du 2026-10-09 :

| Mesure | Prompt | Mesuré |
|---|---|---|
| ViewModel | 7 741 l, 384 969 o | 7 926 l, 399 963 o |
| `.swift` sous `StarHubTH/` | 534 | 608 |
| `Models/` · `Views/` | 301 · 166 | 334 · 191 |
| `Views/Components/` · `Views/Performance/` | 52 · 20 | 56 · 31 |
| `Stores/` (dont `*Store.swift`) | 35 (30) | 44 (35) |
| `Extensions/` · racine | 2 · 29 | 3 · 36 |
| Fichiers `@Observable` | 31 | 38 |
| Lignes `@Published` | 22 | 18 |
| Fichiers de test · `@Test` · `@Suite` · cibles | 341 · 4 050 · 163 · 233 | 381 · 4 371 · 178 · 245 |
| `.cs` de `companion/` | 42 | 40 |
| `Package.swift` · `README.md` · `CHANGELOG.md` | 57 266 · 34 080 · 313 494 o | 61 352 · 20 738 · 327 536 o |

Les cinq `ObservableObject` sont inchangés ; la classe de
`Models/ModListFilters.swift` s'appelle `ModListState`. `AGENTS.md` annonçait
encore « ~10 000 lignes » (§5.1) et 3 424 tests (§2, §8).

# Phase 1 — `StarHubTH/StarHubTHViewModel.swift`

`git diff dfb8fce4..343a0421` : +426/−184, 35 commits.

## 🔴 Bugs bloquants

Aucun.

## 🟡 Bugs mineurs

### X120 — Une archive sans rapport hérite des dépendances attendues d'un téléchargement abandonné

- **Où** : `StarHubTH/Views/MainView.swift:422` (`onDismiss` de la feuille
  de téléchargement).
- **Cause** : la fermeture efface `pendingNexusSource`, pas
  `MissingDependencyStore.pendingExpectedIds`, alors que le store promet un
  effacement « aux mêmes endroits ». Deux chemins ouvrent ensuite
  `ModInstallView` sans effacer : `reinstallFromArchive` (archive conservée,
  X103-C) et `pendingDropPresentation`. Les chemins dépôt et sélecteur de
  fichier internes à `ModInstallView` effacent, eux.
- **Scénario** : télécharger une dépendance manquante (A1-T1), fermer la
  feuille sans installer, réinstaller une autre archive conservée.
  `InstallPreview.expectedMissing` annonce que l'archive ne fournit pas la
  dépendance attendue.
- **Correctif proposé** (une ligne, sous la ligne 422) :
  ```swift
  vm.clearPendingDependencyExpectation()
  ```

### X121 — « Vérifier sur Nexus » peut laisser la vérification « en cours » pour la session

- **Où** : `StarHubTHViewModel.checkUpdatesViaNexus()` et
  `recheckBlockedViaNexus(_:)`.
- **Cause** : `beginFallback(pages: 0)` lève `fallbackInFlight` avant
  l'`await` du tri sans clé (903 pages à 80 par requête : 12 requêtes
  GraphQL en série). Si la clé disparaît du Trousseau pendant ce tri,
  `recheckBlockedViaNexus` sort par son garde de clé sans `endFallback()`.
  `isChecking` reste vrai : Vérifier est refusé, Arrêter pose un
  `stopRequested` que plus personne ne lit, l'auto-vérification est bloquée.
  Seul un redémarrage rend la main.
- **Fenêtre** : le seul effacement de clé est le bouton des Réglages
  (`SettingsView.swift:179`) ; aucun effacement automatique sur 401. Étroite,
  mais sans recours. Même famille que le défaut décrit dans la doc
  d'`endFallback` (« un drapeau resté levé laisserait la vérification bloquée
  “en cours” pour la session »).
- **Correctif proposé** (isolation `@MainActor` héritée de la `Task`) :
  ```swift
  guard !updateStore.stopRequested, !kept.isEmpty,
        NexusUpdateChecker.shared.apiKey()?.isEmpty == false
  else { return updateStore.endFallback() }
  ```

## 🔧 Fonctionnalités prévues non implémentées

Aucun TODO, FIXME ni `fatalError("TODO")` dans le delta.

## ⚠️ Anti-patterns

- `healthIssues` relit et décode `install_metadata.json` (100 Ko sur le
  poste de référence) à **chaque accès** dès qu'au moins un manifeste est
  illisible ; `systemAlertCount` et `modConflictCount` l'appellent à chaque
  rendu de la barre latérale. Relève de **F3** (ouvert). Non mesuré : compter
  d'abord les manifestes illisibles du parc, puis chronométrer.
- Écart de spécification, pas un bug : la règle F1-T2 est respectée par les
  types neufs (`MissingDependencyStore`, `BulkConflictGateStore`,
  `ActivationHistoryStore`…), mais le cliquet de taille du ViewModel a été
  relevé par 27 commits depuis le 2026-10-01 (+185 lignes nettes).

## 🔗 Carte de dépendances

- **Le delta appelle** : `ModUpdateStore` (numéro de passe, arrêt, reprise
  Nexus), `MissingDependencyStore`, `BulkConflictGateStore`,
  `ActivationHistoryStore`, `ContentPatcherLoadIndex`,
  `HiddenCodeDependencyIndex`, `SmapiLocalMetadata`, `ManifestRepair`,
  `NexusModStatsRefresher`.
- **Lu par les vues** : `UpdatesView` (`isCheckingNexusUpdates`,
  progression, bouton Arrêter), `InstallPreview`
  (`pendingExpectedDependencyIds`), `SystemAlertsView` et la barre latérale
  (`healthIssues`).
- **Portée** : X121 bloque toute vérification de mises à jour jusqu'au
  redémarrage ; X120 affiche un faux avertissement à l'installation.

## ✅ Ce qui fonctionne

- Une passe arrêtée pendant smapi.io voit sa complétion ignorée
  (`passNumber`) ; `endCheck` laisse la reprise Nexus refermer la passe.
- Le tri sans clé garde une page quand sa statistique manque : une panne du
  tri ne vide rien.
- R5 : le retour passe par les mêmes portes que les gestes groupés
  (empreintes, conflits) ; le profil d'alors n'est réactivé qu'après le
  rescan.
- `restoreManifest` écrit dans le dossier physique résolu depuis le parc, et
  un échec reste au journal.
- F6-T1 : la garde de génération de la couverture FR est câblée.

## 🔬 Pistes écartées, avec la mesure

- **`return` sur `targets` vide dans `recheckBlockedViaNexus`** : inatteignable
  depuis `checkUpdatesViaNexus`. Re-planifier `kept.flatMap(\.mods)` redonne
  les mêmes groupes non vides (mêmes filtres `needsNexusVerdict`,
  `isAmbiguous`).
- **Arrêter pendant smapi.io ne coupe pas la requête** : `SmapiUpdateClient`
  n'annule rien (X87 sérialise), une relance attend la passe abandonnée. Sur
  les HTTP 500 rapides observés le 2026-10-08 : quelques secondes. Ne pèse
  que si smapi.io ne répond plus (`timeoutInterval = 120` par lot). À
  rouvrir si un journal montre une relance longue.
- **Progression d'une passe arrêtée affichée dans la suivante** (closures
  `progress:` et `setProgress(nil)` non gardées par `pass`) : passager,
  visuel, affiché seulement sous `isCheckingNexusUpdates`.
- **`contentPatcherLoadIndex.refresh` à chaque bascule** (règle du commit
  `9ae42475`) : hors fil principal, cache par date de modification indexé
  par dossier logique — ~500 `stat()` par bascule, zéro décodage.
- **`ProbeLoadOrder.sync` écrit `config.user.json` avant le garde « jeu
  lancé »** : SMAPI ne lit ce fichier qu'au démarrage ; écriture idempotente
  avec copie `.bak`.
- **`smapi-internal/metadata.json` lu sur le fil principal** : 44 Ko, lu
  seulement après un échec smapi.io.
- **`ManifestRepair.backupManifest` : `split("/")[0]` sur un nom vide** : le
  scanner ne produit jamais de `folderName` vide.
- **Instantané R5 en trop quand `applyProfile(nil)` est refusé** :
  `ActivationHistory.record` ignore un état identique au plus récent — au
  plus une ligne, inerte si on la rejoue.
- **`autoCheckUpdatesIfDue` lit `updateStore.lastCheckedAt`** : initialisé
  depuis `NexusUpdateChecker.shared.lastSuccessfulCheck`, donc la règle des
  12 h survit au redémarrage.

---

# Phase 1 — `StarHubTH/Stores/`

19 fichiers touchés, dont 11 créés (`ActivationHistoryStore`,
`BulkConflictGateStore`, `ContentPatcherLoadIndex`,
`HiddenCodeDependencyIndex`, `MissingDependencyStore`, `ModImpactStore`,
`NexusEndorsementStore`, `NexusModStatsRefresher`, `SessionEnvironmentStore`,
`SloDiagnosticSessionStore` et son extension `+Completion`). Diffs lus :
`BenchmarkRunner`, `FrenchTranslationSweepStore`, `ProbePerformanceStore`,
`ModUpdateStore`, `NavigationStore`, `ScanStore`, `ErrorHistoryStore`.
`AppDesignCore.swift` : une constante d'ombre ajoutée, rien à signaler.

**Bilan : 0 🔴, 1 🟡 (X122), 8 pistes écartées.**

## 🟡 X122 — L'impact par mod dépend de l'onglet Mods : jamais chargé depuis Performances, figé ensuite

- **Où** : `Stores/ModImpactStore.swift`, ses trois déclencheurs
  (`ModListView.swift:450`, `ModImpactSection` de la fiche,
  `GameExitRefresh`).
- **Cause 1 — premier chargement** : seuls la liste des mods et la fiche
  appellent `reloadIfIdle`. `PerformanceView.task` recharge son propre store
  et l'environnement, pas `modImpactStore`. Lancer l'app (onglet Accueil par
  défaut) puis ouvrir Journaux › Performances : les cartes « Impact par mod »
  et « Textures » restent sur leur indicateur de chargement (`.idle`)
  jusqu'à la visite de l'onglet Mods ou la fermeture du jeu.
- **Cause 2 — état figé** : `ModImpact.entries(history:mods:)` copie
  `isEnabled` de chaque mod au moment de la relecture
  (`ModImpact.swift:183`). Classement, lignes de performance et textures
  filtrent sur cette copie (`ModImpact.swift:191`,
  `ProbeImpactPresentation.swift:16,66`), et la fiche affiche « en pause »
  d'après elle. Or la relecture n'a lieu qu'une fois (`reloadIfIdle`) puis à
  la fermeture du jeu. Mettre en pause un mod mesuré : il reste classé parmi
  les actifs et sa fiche ne dit pas « en pause » ; activer un mod en pause :
  l'inverse. Changer de dossier de jeu garde les entrées de l'ancien parc.
- **Correctif proposé** : le store garde le dernier `ModImpactHistory` lu et
  expose une re-dérivation sans entrée-sortie (`ModImpact.entries` + les
  tables qui en découlent) appelée quand `mods` change ;
  `PerformanceView.task` appelle `reloadIfIdle` comme la liste.

## 🔬 Pistes écartées (Stores)

- **`BulkConflictGateStore` : bouton Confirmer suivi du `set(false)` de la
  liaison** — si SwiftUI appelait `set(false)` avant l'action, `cancel()`
  viderait `onResume` et Confirmer ne reprendrait rien. Même patron que
  l'alerte d'empreintes (A1-T8) en service depuis des semaines : l'ordre
  effectif est action puis liaison. Comportement d'interface, à constater à
  l'écran, pas à déduire.
- **`ContentPatcherLoadIndex` : cache sur la seule date du `content.json`**
  alors que `ContentPatcherPacks.read` suit les inclusions. Un fichier
  inclus modifié sans toucher `content.json` garderait des cibles périmées,
  pour la session seulement (cache en mémoire). Une mise à jour de mod
  réécrit le dossier entier ; cas non observé.
- **`NexusEndorsementStore.loadIfNeeded` : `reset()` pendant la requête de
  liste** — la réponse de l'ancien compte s'écrit après l'effacement de la
  clé. Fenêtre d'une requête, aucun geste ne part sans clé (`toggle` relit
  le Trousseau).
- **`HiddenCodeDependencyIndex` : chaque DLL chargée entière en mémoire**
  (`contents` + copie en `[UInt8]`), en série, hors fil principal. 523 DLL,
  une à la fois : pic borné par la plus grosse.
- **`SloDiagnosticSessionStore` : `try?` sur les sauvegardes d'instantané et
  de reçu** (`+Completion.swift:32,47,50,58`). Famille X89, mais chaque
  `try?` suit une écriture réussie du même fichier dans le même dossier ; un
  instantané non effacé est repris et restauré au lancement suivant.
- **`SloDiagnosticSessionStore` : `gameExited` et la boucle de surveillance
  peuvent appeler `finalize` ensemble** — gardé par `finalizing`.
- **`FrenchTranslationSweepStore` : un résultat valable jeté quand l'autre
  chercheur reçoit un 429 entre-temps** — voulu (« rien de ce qui revient ne
  s'écrit ») ; le mod sera re-cherché au passage suivant.
  `currentNames.removeAll` retire aussi un homonyme en cours : visuel.
- **`ProbePerformanceStore.select` : garde `a.id != b.id` retirée** — la même
  sélection est désormais qualifiée (`ProbeComparisonScope.Issue.sameSelection`),
  voulu par `de3a9c2b`.

---

# Phase 1 — `StarHubTH/Models/`

121 fichiers touchés (+8 516 lignes), dont 60 créés. Lus en entier : ce qui
écrit sur le disque ou parle au réseau, et les parseurs neufs —
`DotNetMetadata` + `HiddenCodeDependencies` (A5-T6), `TranslationUpdate` (et
son appel dans `ModZipInstaller`), `ProbeBundle`, `NexusRequestBuilder`,
`SloDiagnosticTransaction` / `Exclusion` (et le runtime construit par
`PerformanceView`), `SmapiLocalMetadata`, `MissingDependencies`. Le reste
(présentation `Probe*`, `Keybind*`, `SloDiagnosticLog`/`Report`,
`ModlistReport`…) passé au balayage de motifs sur tout le delta : indices
`[0]`, force-unwrap, `try!`, `try?` sur une écriture, `ForEach(id: \.self)`,
clés `UserDefaults` littérales, `waitUntilExit`, `DispatchQueue.main.sync`.
Chaque occurrence relevée a été vérifiée à la main ; aucune ne plante.

**Bilan : 0 🔴, 0 🟡 neuf.**

## 🔬 Pistes écartées (Models)

- **`DotNetMetadata` : lectures hors bornes sur une DLL tronquée ou
  étrangère** — chaque lecture passe par `u16`/`u32`/`u64` bornés ou une
  garde de plage avant l'indice ; `compressedUInt` refuse un tampon
  tronqué ; `Range` jamais inversée (taille non signée). Aucun indice brut
  non gardé trouvé.
- **`HiddenCodeDependencies` : nombre de lignes déclaré absurde** — une DLL
  corrompue annonçant ~4·10⁹ lignes dans `TypeDef` ou `NestedClass` ferait
  tourner `typeDefFullNames()` des milliards de fois (chaque appel échoue
  sur ses bornes, sans planter), en tâche de fond `utility`, et le résultat
  ne serait jamais mis en cache. Les 523 DLL du parc se lisent en ~10 s :
  aucun cas réel. Durcissement possible, non posé : refuser dans
  `MetadataFile.init` des tables dont la taille totale dépasse le stream
  `#~`.
- **`TranslationUpdate.apply(.takeAuthor)` dans un `i18n/` en 0555** — même
  dossier que `restoreUserConfigs`, qui y écrit juste avant ; le droit
  d'écriture est déjà exigé par le chemin existant (X7/X17).
- **`TranslationUpdate.apply(.merge)` sort en silence** si la locale ne se
  relit pas — inatteignable : l'aperçu ne propose le choix que pour des
  fichiers que `comparisons` a déjà lus des deux côtés avec le même
  parseur.
- **`TranslationUpdate.merged` réécrit en UTF-8, fins de ligne `\n`** sur un
  fichier d'origine UTF-16 ou CRLF : Newtonsoft lit les deux, et
  `I18nFileDecoder` a déjà rendu le texte en Unicode.
- **`ProbeBundle.install` : remplacement fichier par fichier, non
  atomique** — une copie ratée laisse la sonde sans DLL (SMAPI la saute,
  l'erreur remonte, la réinstallation répare). `config.json` n'est pas
  embarqué (`build_app.py` : DLL, manifeste, licence, `i18n/`) : les
  options de l'utilisateur survivent à la mise à jour.
- **Requêtes Nexus hors `NexusRequestBuilder`** — les trois constructeurs
  neufs (`makeJSONPost`, `makeGraphQLRequest`, `makeManifestRequest`) y
  vivent ; le seul `URLRequest(url:)` hors du fichier vise
  `appReleaseURL` (GitHub), pas Nexus.
- **`SmapiLocalMetadata.Entry.status` lit les clauses dans l'ordre d'un
  dictionnaire** (non ordonné) : deux clauses `~x | Status` sur une même
  entrée rendraient un verdict au hasard. Mesuré sur le `metadata.json` de
  SMAPI du parc : 188 entrées, **0** avec plus d'une clause `Status`,
  **0** `Id` à plusieurs identifiants séparés par virgule. À rouvrir si une
  version de SMAPI en introduit (le parseur lirait alors l'ordre du
  fichier, que `I18nLenientParser.lenientObject` ne garde pas).
- **`MissingDependencies.searchPage` encode avec `.urlQueryAllowed`**, qui
  laisse passer `&`, `+` et `=` : un nom portant `&` couperait la recherche
  Nexus au premier mot. Repli de dernier recours (ni page Nexus connue ni
  téléchargement possible) ; aucun cas mesuré. Correctif d'une ligne si un
  cas paraît : retirer `&+=` de l'ensemble autorisé.
- **`MissingDependency.id` lit `uniqueIds[0]`** — `plan` n'émet jamais un
  groupe sans identifiant (la clé n'est créée qu'avec le premier).
- **`SloDiagnosticTransaction.prepare` réécrit la config de SLO par
  `JSONSerialization`** (commentaires et ordre perdus) : pendant la seule
  durée du diagnostic ; l'original revient **à l'octet** (`originalConfig`),
  et une config touchée entre-temps bloque la restauration au lieu de
  l'écraser (`restoreDecision` → `.conflict`).
- **`SloDiagnosticRuntime.matches` vaut `true` sans `modsRootURL`** — le seul
  constructeur (`PerformanceView.swift:213`) le renseigne.
- **`NexusArchiveStore` : deux mods au même `UniqueID@version` partagent un
  fichier** (le second écrase le premier). Le parc compte 58 identifiants
  partagés, mais une archive Nexus ne se garde qu'à l'installation d'un
  téléchargement, dont le mod détecté porte l'identifiant ; aucun cas
  observé. Le fichier est toujours nommé `.zip`, même pour un RAR :
  sans effet, la réinstallation recopie sous `fileName` d'origine et
  l'installateur juge les octets.
- **`ActivationRestore.moves`** : ne touche que les mods nommés par
  l'instantané (un mod installé depuis reste tel quel), jamais un mod
  livré avec SMAPI, chemins source par `physicalFolderName`.
- **`ContentPatcherPatches.certainLoadTargets` ignore le champ `Enabled`**
  (format Content Patcher 1.x) : un `Load` désactivé compterait comme
  certain. Mesuré sur le parc : 1 544 fichiers JSON portent un `Load`, **1**
  porte un champ `Enabled`.
- **`ModImpactHistory` grossit d'une entrée par session intégrée**
  (`integrated`, `boots`) : quelques dizaines d'octets chacune, plafond de
  30 échantillons par version et par nature. Sans conséquence à l'échelle
  d'années.
- **`ModListSelection`** (I-T20) : sélection par `folderName`, toujours
  relue à travers l'ordre visible (`members(in:)`) — un mod filtré ou
  désinstallé ne reçoit pas le geste.
- **`SloDiagnosticContract.discover`** : chemin initial par
  `physicalFolderName`, chemin actif par `folderName` — le point d'un mod
  en pause est pris en compte des deux côtés.

# Phase 1 — `StarHubTH/Views/`

137 fichiers touchés (+8 881/−2 935). Balayage de motifs (voir Models) et
recherche des entrées-sorties ajoutées dans une vue : lectures de
`CHANGELOG.md` (`AppChangelogView`, une fois), options de la sonde
(`ProbeOptionsSection` : petit fichier, écriture atomique, droits ouverts
avant — piège 0555), ouvertures de pages. X120 (`MainView.swift:422`) vient
de cette passe.

## 🔬 Pistes écartées (Views)

- **`ForEach(…, id: \.self)` sur des chaînes** (22 occurrences ajoutées) :
  listes fixes ou d'éléments uniques par construction (`Set` trié, cas
  d'énumération, liens `Hashable`). Seule exception possible :
  `PerformanceEnvironmentSection.swift:183` liste les packs illisibles par
  **nom affiché**, et deux composants peuvent porter le même nom — une
  ligne en double ne s'afficherait pas. Visuel, sur une liste repliée ;
  identifiant stable conseillé (`folderName`) au prochain passage dans ce
  fichier.
- **`BenchmarkPanelWindow.swift:197` : `ForEach(runner.runs.indices,
  id: \.self)`** — la série est figée pendant son affichage.
- **`PerformanceEnvironmentSection.swift:110-111` : `opt!.configured!`**
  derrière un test `== nil` du même optionnel sur la même ligne : sûr,
  illisible ; `map` conseillé, sans urgence.
- **`PerformanceStardropiumDiagnosticControls.swift:131` pose une attente de
  dépendance puis ouvre la page Nexus** : voulu — l'archive arrivera par
  `nxm://` et `takeExpectation` la reprendra.

# Phase 2 — Intégrations réseau

Delta depuis l'audit du 2026-09-07 (`c0b54852..`). Clients **nés depuis** :
`SmapiBlacklist` (liste noire SMAPI), `NexusFileManifestFetcher`
(manifestes de fichiers Nexus), `NexusDownloadStore`,
`NexusEndorsementStore`, `NexusModStatsRefresher`. Modifiés :
`SmapiInstaller`, `NexusUpdateChecker`, `SmapiUpdateClient`,
`NexusSearchClient`, `DeepLClient`, `PathoschildCompatibilityList`,
`NexusDownloadAPI`. X121 relève de cette phase (orchestration VM).

**Bilan : 0 🔴, 0 🟡 neuf hors X121.**

## 🔬 Pistes écartées (réseau)

- **Constructeur unique Nexus** : toutes les requêtes Nexus neuves passent
  par `NexusRequestBuilder` (`makeRequest`, `makeJSONPost`,
  `makeGraphQLRequest`, `makeManifestRequest`).
- **Cache d'octets étrangers** : `SmapiBlacklist.outcome(forPayload:)` et
  `NexusFileManifestFetcher.read` n'écrivent le cache qu'après décodage
  réussi — la leçon du 200 illisible est appliquée aux deux.
- **`NexusFileManifestFetcher.liveTransport` bloque sur un sémaphore** :
  appelé seulement depuis la file de fond de l'installateur et un
  `DispatchQueue.global` (`ModCleanupSheet.analyze`) ; `concurrentPerform`
  remplace l'`OperationQueue` qui gelait la CI (commentaire daté).
- **`SmapiInstaller` : lecture bornée du tube**, coupée en taille et en
  durée — mais la durée n'est relue qu'à l'arrivée d'un morceau : un
  installateur **muet** et bloqué tiendrait la lecture indéfiniment. Le
  cas mesuré est l'inverse (6 Mo/s de questions répétées) ; aucun blocage
  muet observé. À rouvrir sur un signalement.
- **`try?` sur l'écriture du journal de l'installateur** : tampon de
  diagnostic, écrasé à chaque passe ; son échec ne change pas le résultat.
- **`NexusEndorsementStore.loadIfNeeded` et `reset()`** : voir Stores.
- **Diffs relus ligne à ligne** (deuxième passe du 2026-10-09) :
  `DeepLClient` (la variable statique `lastResponse`, partagée entre appels
  concurrents, est remplacée par un couple rendu par `send` — une course de
  moins), `NexusSearchClient` (repli v2 sans clé limité à
  `modDetailRaw` par `requiresKey: false`), `PathoschildCompatibilityList`
  (chemin du cache passé par `AppSupport`), `SmapiUpdateClient` (prise et
  pose de `inFlight` d'un seul tenant), `NexusDownloadAPI` (messages
  rendus au Core), `NexusUpdateChecker` (`mergeCachedExtras` sous le
  verrou du cache). `NexusDownloadStore` n'est pas `@MainActor` mais toutes
  ses mutations passent sur le fil principal
  (`noteNexusDownloadProgress` saute explicitement). Rien à corriger.
- **`fetchRawDescription` rappelle sa complétion depuis le fil d'URLSession** :
  `ModDetailRefresh` relaie, et le ViewModel saute sur le fil principal
  avant de toucher l'état (`DispatchQueue.main.async`, garde anti-course
  sur le mod affiché).

# Phase 3 — Persistance

Delta depuis le 2026-09-07. Stores persistants nés depuis :
`NexusArchiveStore` (X103-C), `ModUpdateKeyDeltaStore`,
`NexusPageStateStore` ; modifiés : `SaveManager` (copie de sauvegarde pour le
benchmark), `ModVersionAnchorStore` (F6-T4), `ModConfigBackupManager`,
`ModInstallBackupManager`, `KeychainSecret`, `UDKey`. X123 vient de cette
passe.

## 🟡 X123 — Un index d'archives illisible fait oublier toutes les archives

- **Où** : `Models/NexusArchiveStore.swift`, `loadIndex()` (L.215-218).
- **Cause** : un `index.json` présent mais illisible se relit comme une
  liste vide. `keep` ajoute alors la nouvelle archive à cette liste vide et
  l'**écrit** : l'index ne connaît plus qu'elle. Les archives déjà sur le
  disque restent dans `files/`, mais `entries()`, `totalBytes()` (la carte
  de stockage) et `applyRetention()` ne lisent que l'index : elles pèsent
  sans être ni montrées ni nettoyées. `remove` et `applyRetention`
  réécrivent de même un index amputé.
- **Même famille** : X76 (`ModInstallBackupManager`, « absent et corrompu
  sont le même non »), et la mise de côté d'`ActivationHistoryStore.load`.
- **Fréquence** : les écritures sont atomiques ; il faut un fichier abîmé
  hors de l'app. Rare, mais sans recours dans l'interface.
- **Correctif proposé** : `loadIndex()` rend `(entries, readable)`. Index
  présent et illisible : le mettre de côté (`index.unreadable-<epoch>.json`)
  et refuser d'écrire tant qu'il n'a pas été reconstruit ; reconstruction
  possible depuis `files/` (le nom porte `UniqueID@version`, la taille se
  relit ; `modName` et date se perdent).
- **Preuve, exécutée le 2026-10-09** (binaire jetable compilé sur
  `NexusArchiveStore.swift`, dossier temporaire) : deux archives gardées,
  `index.json` remplacé par `{ pas du json`, `keep` d'une troisième →
  `entries().count == 1`, trois fichiers dans `files/`,
  `applyRetention()` rend 0.

## 🔬 Pistes écartées (persistance)

- **Collision de clés `UDKey`** : aucune valeur en double.
- **Clés `UserDefaults` hors `UDKey`** (convention AGENTS §4.3) : cinq,
  antérieures au delta — `nexusQuota`, `nexusAccount`
  (`NexusUpdateChecker`), `favoriteMods`, `blacklistedMods`,
  `defaultProfileId` (ViewModel). Toutes figurent dans la liste de
  `DefaultsMigration` : rien ne s'est perdu au changement d'identifiant
  (F5). Écart de convention, pas défaut ; à déplacer vers `UDKey` lors d'un
  passage dans ces fichiers.
- **`ModUpdateKeyDeltaStore` : `try?` au décodage et à la suppression** —
  une lecture ratée vaut « pas de delta connu », une suppression ratée
  laisse un fichier que la lecture suivante rejoue ; l'écriture, elle,
  propage.
- **`SaveManager.cloneForBenchmark`** réutilise `cloneSaveFolder`, déjà
  audité (copie sous un nouveau nom, original intact).

# Phase 4 — Tests

- **Miroir `Package.swift` ↔ `Tests/`** : 245 cibles, 245 dossiers, aucun
  écart dans un sens ni dans l'autre.
- **Fichiers neufs hors du module Core** : 4 sur 71 créés —
  `Stores/BulkConflictGateStore`, `HiddenCodeDependencyIndex`,
  `NexusEndorsementStore`, `NexusModStatsRefresher`. Colle d'interface
  (réseau, `@Observable`) dont la règle vit dans un type Core testé
  (`ModConflictVerdicts.newConflicts`, `HiddenCodeDependencies`,
  `NexusEndorsement`, `NexusModStats`). Pas un X91. `ModImpactStore`, lui, est
  dans le module Core et a sa suite (`ModImpactStoreTests`) : le test de
  X122 y entre.
- **Tests qui écriraient dans le vrai Application Support** : aucun nouveau
  test n'appelle `AppSupport.directory`, `.shared` d'un gestionnaire de
  sauvegardes, ni `defaultRoot` d'un magasin.
- **Manque de test qui aurait vu X123** : aucun test de
  `NexusArchiveStoreTests` (12) ne pose un index illisible. Le scénario a
  été exécuté hors dépôt (binaire jetable) : il échoue comme décrit.
- **`run_tests.sh`** : inchangé depuis le 2026-10-01.
- **`companion/` (sonde C#, 31 commits, +1 284 lignes)** : relu au balayage,
  sans `dotnet` (hors gate Swift). Chaque accroche Harmony neuve
  (`StartupHooks`) est enveloppée d'un `catch` qui ne remonte jamais dans
  la boucle de SMAPI. Piste écartée : `TextureMemory` tient deux
  `Dictionary` statiques sans verrou, mutés par les événements de contenu
  de SMAPI — sûr tant que ces événements arrivent sur le fil du jeu ; un
  mod qui charge des assets en parallèle (préchauffage SpaceCore, désactivé
  sur le parc : `EnableSpaceCorePrewarm=false`) pourrait les croiser. Non
  observé ; un `lock` coûterait peu si un journal montre une
  `InvalidOperationException` attrapée par les `catch` de `ByOwner`.

# Phase 5 — Configuration, build et déploiement

Delta depuis le 2026-10-01 : `Package.swift` (+156), `build_app.py` (+70 :
parité L10n qui sort en 1 sur un JSON illisible, sonde embarquée),
`check_sources.py` (+29 : sources de la sonde, trois concurrents relevés),
`release.py` (+8), `Info.plist` (version). X124 vient de cette passe.

## 🟡 X124 — `release.py` rend 0 quand il s'interrompt

- **Où** : `release.py`, `create_release()` et `if __name__ == "__main__":
  create_release()`.
- **Cause** : quatre sorties d'échec (compteur de build non incrémenté,
  build en échec, dossier de l'app absent, **sonde non embarquée** —
  ajoutée le 2026-10-03) affichent `[ERROR]` puis font `return` ; l'envoi
  refusé affiche son erreur et la fonction se termine. Dans les cinq cas
  le processus sort en 0. Le prompt d'audit l'exige
  explicitement des scripts de la chaîne, et ce dépôt a déjà payé un
  `exit 0` sur échec. L'audit du 2026-09-07 avait jugé le flux
  (interruption avant le zip), pas le code de sortie.
- **Effet aujourd'hui** : nul tant que la release se lance à la main et se
  lit à l'écran (consigne : répondre « n » puis `gh release create`) ;
  faux succès dès qu'un `&&` ou une CI l'enchaîne.
- **Correctif proposé** : `create_release() -> int`, chaque sortie
  d'erreur rend 1, et `sys.exit(create_release())`. Vérifier par lecture :
  lancer le script incrémente le compteur de build et lance le gate avant
  tout contrôle. Au passage : le
  compteur de build est incrémenté **avant** le build — un build raté
  consomme un numéro (sans gravité, voulu pour que le bundle le porte).

## 🔬 Pistes écartées (build)

- **`build_app.py` embarquerait une sonde périmée** si sa recompilation
  échoue — non : `stale()` refuse d'embarquer une DLL plus ancienne que
  ses sources, et `create_app_bundle` efface le bundle précédent
  (`shutil.rmtree(APP_DIR)`) : aucune sonde d'un build antérieur ne
  survit.
- **`check_standards.py` / `check_sources.py`** : codes de sortie inchangés
  depuis leur vérification du 2026-09-07 ; les ajouts de `check_sources.py`
  sont des lignes de la table des sources. `check_sources.py` n'a pas été
  lancé (consigne d'audit), `.sources-baseline.json` non touché.
- **Cliquet de taille** : relevé à chaque commit pour le ViewModel (voir
  Phase 1) — convention de relèvement assumée par le dépôt, pas une
  défaillance du script.
