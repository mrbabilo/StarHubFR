# Audit du ViewModel — delta du 2026-10-01 au 2026-10-09

Passe du prompt `docs/prompt-audit.md`, limitée à ce qui a changé dans
`StarHubTH/StarHubTHViewModel.swift` depuis le 2026-10-01
(`git diff dfb8fce4..343a0421`, +426/−184, 35 commits : R5, A1-T1, A1-T2,
A2-T5, A3-T8, A5-T4, A5-T6, A5-T8, F6-T1, F6-T3, I-T20, arrêt et repli Nexus
des mises à jour). Le reste du fichier a été audité par tranches le
2026-09-02 (0 bug bloquant). Aucun correctif n'est posé par ce document.

**Bilan : 0 🔴, 2 🟡 (X120, X121), 9 pistes écartées.**

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

# Suite — `StarHubTH/Stores/`, delta du 2026-10-01 au 2026-10-09

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
