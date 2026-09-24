# AGENTS.md — StarHubFR (fork de StarHubTH)

> **LIRE OBLIGATOIREMENT avant toute modification de ce projet.**
> Ce fichier consolide les conventions, pièges techniques et commandes validées.
> Complémentaire à `CLAUDE.md` (qui pointe vers les skills et liste les sources
> à consulter), à `docs/DOMAINE.md` (le vocabulaire métier), à `docs/SOURCES.md`
> (la carte de ce qui vit hors du dépôt : API, dumps, code repris) et à `.kilo/plans/`
> — les plans de l'époque Kilo, qui portent le raisonnement derrière des choix
> encore en place. Ces plans sont des **archives** : à lire pour le « pourquoi »,
> jamais comme une spécification courante.

---

## 1. Identité du projet

- **StarHubFR** — gestionnaire de mods Stardew Valley pour macOS (SwiftUI, macOS 14+).
- Fork de **StarHubTH** (AppleBoiy). Dossier source : `StarHubTH/`. Bundle produit : `StarHubFR.app` (exécutable `StarHubFR`).
- Bundle ID `com.mrbabilo.StarHubFR` (depuis F5, 2026-09-10) : domaine de préférences et Trousseau séparés de l'upstream. L'ancien `com.appleboiy.StarHubTH` reste lu **en secours** (`KeychainSecret.legacyService`, `DefaultsMigration`).
- Données sous `~/Library/Application Support/StarHubFR/` (`Backups/` compris, depuis X105).
- UI **bilingue** : anglais (`en`) + français (`fr`). Le thaï comme langue d'UI est retiré, le « Thai Translation Hub » aussi (C5-T1, 2026-09-24) : la page « Traductions FR » le remplace.

---

## 2. Build & test — COMMANDES EXACTES

### Build de l'app (le vrai gate)
```bash
python3 build_app.py
```
- `swiftc` brut sur **tous** les `.swift` sous `StarHubTH/` (un seul module), en **mode de langage Swift 6** (`-swift-version 6`). Compilation incrémentale ; `--whole-module` rend l'ancien chemin.
- Même exigence que les tests : si `xcode-select -p` pointe sur les Command Line Tools, le build échoue sur `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found` — pas une erreur de code. Préfixer `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Lire son code de sortie directement : `python3 build_app.py | tail` rend celui de `tail`.
- **Toujours `python3`**, jamais `python` (absent du PATH).
- Valide la **parité des clés** `en.json`/`fr.json` (build en erreur sinon).
- Génère `assets/*.lproj/Localizable.strings` + `compile_commands.json` (gitignoré).

### Tests SPM
```bash
./run_tests.sh
# ou manuellement :
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
- **`DEVELOPER_DIR` est OBLIGATOIRE** : le framework `Testing` (Swift Testing, `import Testing`) nécessite **Xcode.app complet**, pas les Command Line Tools.
- Sans `DEVELOPER_DIR` : `no such module 'Testing'` — c'est une **limite d'environnement, pas une régression**.
- 3 424 `@Test`, 134 `@Suite` explicites, 219 cibles de test (relevé du 2026-09-24).
- La CI GitHub (Xcode 16.4, Swift 6.0) est le juge : la chaîne locale est plus récente, un écart de mode de langage n'y apparaît pas.

### `swift build` (Core seulement)
- Ne compile que le sous-ensemble du `Package.swift` (`ModItem`, managers de backup, `SaveManager`, `L10n`, etc.) — **pas** l'UI ni le ViewModel complet.
- Utile pour un check rapide de logique Core, mais ne remplace pas `build_app.py`.

### Les deux cliquets

```bash
python3 check_standards.py --report      # conventions Swift (état, sans juger)
python3 check_sources.py --offline       # sources externes, contrôles locaux seuls
```

- **`check_standards.py`** / `.standards-baseline.json` — cliquet sur les
  conventions Swift, lancé automatiquement par `build_app.py` après une
  compilation réussie. Il n'échoue qu'à l'**augmentation** d'un compteur : le
  code viole massivement ces règles aujourd'hui. Faire baisser puis `--update`
  pour resserrer ; un ajout délibéré exige un `--update` explicite, visible
  dans le diff. `--skip-standards` débloque un build ponctuel.
  La **taille** est verrouillée **par fichier** (clés `file:<chemin>`, une par
  fichier au-dessus de 400 lignes) : les deux sommes de taille se compensaient
  entre fichiers, et laissaient ~16 000 lignes de marge muette au ViewModel
  (mesuré le 2026-09-11 — `docs/REFACTORING.md` §3 bis).
- **`check_sources.py`** / `.sources-baseline.json` — le pendant pour ce qui
  vit **hors** du dépôt : API appelées, dumps téléchargés, projets dont du code
  a été repris. Carte et raisonnement dans `docs/SOURCES.md`.
  ⚠️ **Un écart n'est pas un échec** : une nouvelle version de SMAPI n'est pas
  un bug, c'est une chose à aller regarder — donc on l'explique, on ne le tait
  pas, et `--update` n'est jamais un moyen de faire taire le script.
  Depuis un agent, préférer `--offline` : la passe complète sonde smapi.io,
  GitHub raw et Nexus (les sources injoignables sont de toute façon reportées
  à part, sans compter comme un écart).

### Règle absolue
**Ne jamais lancer l'app ni prendre de capture depuis un agent.** La vérification GUI est déléguée à l'humain ; les agents valident par succès de build + tests.

---

## 3. Localisation — RÈGLES STRICTES

- **Source de vérité** : `assets/{en,fr}.json` (JSON).
- **Ne JAMAIS éditer** `assets/*.lproj/Localizable.strings` — générés par `build_app.py`.
- **Parité obligatoire** : `en.json` et `fr.json` doivent contenir **exactement les mêmes clés**. Le build valide ça.
- Les clés sont référencées via `L10n.swift` (constantes `static let`).
- `localizedString` retourne la clé brute si traduction absente (fallback) — ne pas crasher.
- Après édition des JSON : relancer `build_app.py` pour régénérer les `.strings`.

---

## 4. Conventions de code — PIÈGES CRITIQUES

### 4.1 Toggle de mods = préfixe point (DEPUIS juillet 2026)
- **Un mod désactivé vit dans `Mods/` avec un point en préfixe** : `Mods/.CJBCheats` (SMAPI ignore les dossiers pointés).
- **`ModItem.folderName` est LOGIQUE** (jamais de point) — c'est la clé du registre, des profils, des timestamps, des backups.
- **`ModItem.physicalFolderName`** (computed) donne le nom disque : `.` + folderName si désactivé.
- Le toggle est un **rename atomique même-parent** O(1), pas un déplacement de dossier.
- **Toute construction de chemin disque** doit utiliser `physicalFolderName`, pas `folderName`.
- **`Mods_disabled/` n'existe plus** sauf cas legacy (migration one-shot + avertissement permanent).

### 4.2 Parsing de manifest.json
- **Jamais `.allowFragments`** : un manifest DOIT être un objet JSON ; accepter un scalaire masquerait un fichier corrompu.
- Options de lecture : `.json5Allowed` (si macOS 12+) — les mods Stardew peuvent avoir des commentaires/trailing commas.
- Stripper les commentaires bloc `/* ... */` avant parsing : `rawString.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)`.

### 4.3 UserDefaults — clés centralisées
- **Toutes les clés dans `UDKey.swift`** — jamais de string littérale dans le code.
- Une clé de migration one-shot doit être **retirée à la version N+1** (commentaire dans UDKey.swift).

### 4.4 Appels réseau Nexus
- **Tous via `NexusRequestBuilder.makeRequest(...)`** dans `Models/NexusRequestBuilder.swift`.
- Source unique pour `apiBase`, `gameDomain`, `appName`, headers.
- Requêtes **sérielles** (pas de parallélisme) pour respecter le rate limit.

### 4.5 Parsing des uniqueIds SMAPI
- Format `Author.ModName`. Centralisé dans `Extensions/SmapiUniqueId.swift` : `.smapiModName`, `.smapiAuthor`.

### 4.6 Concurrency / DispatchQueue
- **`weak self` obligatoire** dans toute closure passée à `DispatchQueue.global().async`.
- Le ViewModel et les stores sont `@MainActor @Observable` : **pas de `@Published`** (ne compile plus chez eux) — une `var` stockée est déjà suivie, l'état observable est `private(set)`. Mutations d'état observé **toujours sur main thread**. Cinq types restent `ObservableObject` (`SmapiInstaller`, `BisectionRunner`, `KeybindScanService`, `LocalizationStore`, `ModListFilters`).
- **Une méthode `@MainActor` appelée depuis un fil de fond tue l'app** : le mode Swift 6 le vérifie à l'exécution. Ni le gate ni les tests ne le voient.
- **Toute structure mutable partagée entre scans** (cache de manifests, registre) doit être protégée par un `NSLock` dédié. `scanMods()` tourne sur une queue background et peut s'exécuter **concurrentiellement avec lui-même** (refresh + initial load, activation de profil en course avec un refresh). Sans lock, le subscript setter d'un `Dictionary` provoque un `EXC_BAD_ACCESS` (crash confirmé juillet 2026 sur `manifestCache`).

### 4.7 `Process()` (sous-processus)
- Toujours **setter la locale** à `en_US_POSIX` pour éviter les parsing dépendant de la langue système (unzip, etc.).

### 4.8 Force-unwrap
- **Interdit dans `CodeEditorView`** et à éviter partout. Préférer `guard let` / `if let`.

### 4.9 Symlink `/tmp` → `/private/tmp` (PIÈGE macOS)
- `FileManager.enumerator` renvoie des chemins **résolus** (`/private/tmp/...`) même si le root était `/tmp/...`.
- **Toujours résoudre le `fileURL.path`** via `resolvingSymlinksInPath()` avant un `replacingOccurrences(of: resolvedRoot)`.
- Sinon le chemin relatif calculé est corrompu (`private/.X/...` au lieu de `.X/...`).

### 4.10 `findExistingMod` — group-aware
- Doit chercher dans les `children` des groupes (packs), dont les en-têtes ont un `uniqueId` vide, pour détecter les conflits sur les mods installés en pack.

---

## 5. Architecture — points sensibles

### 5.1 `StarHubTHViewModel` = god-object
- ~10 000 lignes (10 027 au 2026-09-24). `scanMods()`, `performToggle`, `applyProfileToFilesystem`, `toggleAllMods`, `deleteMod`, `cleanDisabledMods`, `syncInstalledModRegistry` y vivent encore.
- Le scan de `Mods/` (dont `parseModFolder`) vit dans `Models/ModScanner.swift`, détenu par le VM (`private let scanner`).
- Refactorisation **en cours** (`docs/REFACTORING.md`) : l'état sort vers `StarHubTH/Stores/` (30 fichiers). Règle F1-T2 : une fonctionnalité neuve naît dans son propre type (store ou type pur dans `Models/`), jamais dans le VM. La taille du VM est verrouillée par le cliquet.

### 5.2 Registre des mods installés
- Porté par `Stores/InstalledModRegistryStore.swift`. UserDefaults key `installedModRegistry` (JSON blob, ~90 Ko).
- Clé de secours `installedModRegistryBackup` + **restauration auto si corruption** + **reconstruction depuis le disque**. ⚠️ Le secours reçoit les **mêmes octets** à chaque écriture : il couvre une clé illisible, pas un retour à la génération précédente.
- Cache en mémoire (thread-safe, NSLock) — un seul decode par session au lieu de 100+ par scan.
- Sync à la fin de chaque `scanMods()` : capture installs par tous moyens (drag-drop, copie manuelle, installer).

### 5.3 Cache de manifests (DEPUIS juillet 2026)
- `manifestCache: [String: (mtime: Date, manifest: [String: Any])]` dans `ModScanner` (`Models/ModScanner.swift`), sous `manifestCacheLock`. Une classe, pas une valeur : deux scans concurrents doivent partager le même cache.
- Key = chemin absolu du manifest.json. Hit = mtime identique → reuse du JSON décodé.
- Un rescan sans changement = ~N `stat()` + 0 decode.

### 5.4 Scanner — énumération à deux niveaux
- **Niveau 1 (top-level)** : `contentsOfDirectory` **sans** `skipsHiddenFiles` → voit les `.X`.
- Classification manuelle : `.X` = désactivé, `X` = activé, OS junk = skip.
- **Niveau 2 (sous-scan récursif)** : `enumerator` **avec** `.skipsHiddenFiles` → cache le junk imbriqué (`.DS_Store`, `.git/`, `._Foo`).
- `relativePath` calculé **relativement au physicalRoot** (le dossier entry), pas à `modsPath` — sinon le point fuit dans `folderName`.

### 5.5 Drag-and-drop install
- **NE JAMAIS écraser** `config.json` ni `fr.json` d'un mod existant (conflit signalé).
- Nouveau mod → désactivé par défaut (`Mods/.X`).
- Update d'un mod **activé** → reste activé (`Mods/X`).

### 5.6 Backups
- `ModInstallBackupManager` (install) et `ModConfigBackupManager` (config) sont **distincts, non consolidés**.
- Rétention hybride 3 niveaux pour les backups d'installation.
- `restoreBackup` restaure en **désactivé** (`Mods/.X`).

---

## 6. UI — contraintes fixes

- **Sidebar** : pas de barre de recherche. « Mod Updates » **toujours visible** (badge caché si 0).
- **Pages de liste** (`ModListView`, `LogsView`) : pattern `VStack(spacing: 0)` avec header fixe + Divider + ScrollView + footer/pagination fixe.
- **Pagination** : 12 mods/page (`ModListView.pageSize`), saut de page direct.
- **Splash de lancement** : fenêtre séparée (`NSPanel`, `Views/LaunchSplashWindow.swift`) avec cover art, barre de progression par phases, menus natifs masqués pendant le chargement. Deux pièges AppKit ont tué l'app au lancement : `applicationShouldTerminateAfterLastWindowClosed` doit rendre `false`, et la fenêtre principale se masque dans `applicationWillFinishLaunching`, pas dans `.onAppear`.

---

## 7. Git & release

- Travailler sur `main`.
- **Pousser uniquement quand l'utilisateur le demande explicitement.** Fetcher et rebaser avant : d'autres sessions poussent aussi sur `main`.
- Commits : style conventional (`feat:`, `fix:`, `chore:`, `docs:`).
- `CHANGELOG.md` : format Keep a Changelog. La section `[Unreleased]` est **intégrée à la prochaine release, jamais supprimée**.
- Workflow release : `release.py` bump la version dans le code source + CHANGELOG. Bundle dans `bundles/` avec préfixe `StarHubFR_v<version>.zip`.

---

## 8. Résumé — checklist avant de valider un changement

1. [ ] `python3 build_app.py` passe sans erreur (compile + parité L10n).
2. [ ] `./run_tests.sh` passe (~3 400 tests).
3. [ ] Si touché `en.json`/`fr.json` : parité des clés + messages cohérents dans les deux langues.
4. [ ] Si touché un chemin disque de mod : utilise `physicalFolderName`, pas `folderName`.
5. [ ] Si nouveau code réseau : passe par `NexusRequestBuilder`.
6. [ ] Si nouveau code asynchrone : `weak self` + mutations sur main ; aucune méthode `@MainActor` appelée depuis un fil de fond.
7. [ ] Si nouvelle fonctionnalité : dans un store ou un type pur, pas dans le ViewModel (F1-T2).
8. [ ] Si parsing de manifest : pas de `.allowFragments`, strip des commentaires.
9. [ ] Si énumération de fichiers : résoudre les symlinks avant comparaison de chemins.
10. [ ] Si touché une URL, un chemin d'API, un en-tête ou une constante de
       contrat externe : `python3 check_sources.py --offline` — et **expliquer**
       l'écart au lieu de le taire (un écart n'est pas un échec ; `--update`
       n'est pas un moyen de faire taire le script).
11. [ ] CHANGELOG mis à jour si changement utilisateur-visible.
12. [ ] Pas de lancement d'app ni capture depuis l'agent.

<!-- caveman-begin -->
Respond terse like smart caveman. All technical substance stay. Only fluff die.

Rules:
- Drop: articles (a/an/the), filler (just/really/basically), pleasantries, hedging
- Fragments OK. Short synonyms. Technical terms exact. Code unchanged.
- Pattern: [thing] [action] [reason]. [next step].
- Not: "Sure! I'd be happy to help you with that."
- Yes: "Bug in auth middleware. Fix:"

Switch level: /caveman lite|full|ultra|wenyan-lite|wenyan-full|wenyan-ultra
Stop: "stop caveman" or "normal mode"

Auto-Clarity: drop caveman for security warnings, irreversible actions, user confused. Resume after.

Boundaries: code/commits/PRs written normal.
<!-- caveman-end -->
