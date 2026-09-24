# AGENTS.md — StarHubFR (fork de StarHubTH)

> **LIRE OBLIGATOIREMENT avant toute modification de ce projet.**
> Conventions, pièges techniques, commandes validées. Complète `CLAUDE.md`
> (pointe vers skills + sources), `docs/DOMAINE.md` (vocabulaire métier),
> `docs/SOURCES.md` (carte hors-dépôt : API, dumps, code repris) et
> `.kilo/plans/` — plans ère Kilo, raisonnement derrière choix en place.
> Plans = **archives** : lire pour « pourquoi », jamais comme spec courante.

---

## 1. Identité du projet

- **StarHubFR** — gestionnaire mods Stardew Valley macOS (SwiftUI, macOS 14+).
- Fork de **StarHubTH** (AppleBoiy). Source : `StarHubTH/`. Bundle : `StarHubFR.app` (exécutable `StarHubFR`).
- Bundle ID `com.mrbabilo.StarHubFR` (F5, 2026-09-10) : préférences + Trousseau séparés de l'upstream. Ancien `com.appleboiy.StarHubTH` lu **en secours** (`KeychainSecret.legacyService`, `DefaultsMigration`).
- Données sous `~/Library/Application Support/StarHubFR/` (`Backups/` compris, depuis X105).
- UI **bilingue** : `en` + `fr`. Thaï UI retiré, « Thai Translation Hub » aussi (C5-T1, 2026-09-24) : remplacé par page « Traductions FR ».

---

## 2. Build & test — COMMANDES EXACTES

### Build de l'app (le vrai gate)
```bash
python3 build_app.py
```
- `swiftc` brut sur **tous** `.swift` sous `StarHubTH/` (un module), **mode Swift 6** (`-swift-version 6`). Incrémental ; `--whole-module` = ancien chemin.
- Si `xcode-select -p` pointe sur Command Line Tools : échec `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found` — pas erreur de code. Préfixer `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Lire code de sortie direct : `python3 build_app.py | tail` rend celui de `tail`.
- **Toujours `python3`**, jamais `python` (absent du PATH).
- Valide **parité clés** `en.json`/`fr.json` (build en erreur sinon).
- Génère `assets/*.lproj/Localizable.strings` + `compile_commands.json` (gitignoré).

### Tests SPM
```bash
./run_tests.sh
# ou manuellement :
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
- **`DEVELOPER_DIR` OBLIGATOIRE** : `Testing` (Swift Testing, `import Testing`) exige **Xcode.app complet**, pas Command Line Tools.
- Sans `DEVELOPER_DIR` : `no such module 'Testing'` — **limite d'environnement, pas régression**.
- 3 424 `@Test`, 134 `@Suite` explicites, 219 cibles (relevé 2026-09-24).
- CI GitHub (Xcode 16.4, Swift 6.0) = juge : chaîne locale plus récente, écart de mode de langage invisible en local.

### `swift build` (Core seulement)
- Compile seulement sous-ensemble `Package.swift` (`ModItem`, managers backup, `SaveManager`, `L10n`, etc.) — **pas** UI ni ViewModel complet.
- Check rapide logique Core ; ne remplace pas `build_app.py`.

### Les deux cliquets

```bash
python3 check_standards.py --report      # conventions Swift (état, sans juger)
python3 check_sources.py --offline       # sources externes, contrôles locaux seuls
```

- **`check_standards.py`** / `.standards-baseline.json` — cliquet conventions
  Swift, lancé par `build_app.py` après compilation réussie. Échoue seulement
  si compteur **augmente** (code viole massivement ces règles aujourd'hui).
  Baisser puis `--update` pour resserrer ; ajout délibéré = `--update`
  explicite, visible au diff. `--skip-standards` débloque build ponctuel.
  **Taille** verrouillée **par fichier** (clés `file:<chemin>`, une par
  fichier > 400 lignes) : les deux sommes se compensaient entre fichiers,
  ~16 000 lignes de marge muette au ViewModel (mesuré 2026-09-11 —
  `docs/REFACTORING.md` §3 bis).
- **`check_sources.py`** / `.sources-baseline.json` — pendant pour le **hors**
  dépôt : API appelées, dumps téléchargés, projets dont code repris. Carte +
  raisonnement : `docs/SOURCES.md`.
  ⚠️ **Écart ≠ échec** : nouvelle version SMAPI = chose à regarder, pas bug
  — l'expliquer, pas la taire ; `--update` jamais pour faire taire le script.
  Depuis agent : `--offline` (passe complète sonde smapi.io, GitHub raw,
  Nexus ; sources injoignables reportées à part, hors écarts).

### Règle absolue
**Ne jamais lancer l'app ni prendre de capture depuis un agent.** Vérif GUI déléguée à l'humain ; agents valident par build + tests.

---

## 3. Localisation — RÈGLES STRICTES

- **Source de vérité** : `assets/{en,fr}.json` (JSON).
- **Ne JAMAIS éditer** `assets/*.lproj/Localizable.strings` — générés par `build_app.py`.
- **Parité obligatoire** : `en.json` et `fr.json` = **exactement mêmes clés**. Build valide.
- Clés référencées via `L10n.swift` (constantes `static let`).
- `localizedString` rend clé brute si traduction absente (fallback) — pas de crash.
- Après édition JSON : relancer `build_app.py` pour régénérer `.strings`.

---

## 4. Conventions de code — PIÈGES CRITIQUES

### 4.1 Toggle de mods = préfixe point (DEPUIS juillet 2026)
- **Mod désactivé vit dans `Mods/` préfixé d'un point** : `Mods/.CJBCheats` (SMAPI ignore dossiers pointés).
- **`ModItem.folderName` est LOGIQUE** (jamais de point) — clé du registre, profils, timestamps, backups.
- **`ModItem.physicalFolderName`** (computed) = nom disque : `.` + folderName si désactivé.
- Toggle = **rename atomique même-parent** O(1), pas déplacement.
- **Tout chemin disque** utilise `physicalFolderName`, pas `folderName`.
- **`Mods_disabled/` n'existe plus** sauf legacy (migration one-shot + avertissement permanent).

### 4.2 Parsing de manifest.json
- **Jamais `.allowFragments`** : manifest DOIT être objet JSON ; accepter scalaire masquerait fichier corrompu.
- Options : `.json5Allowed` (macOS 12+) — mods Stardew ont commentaires/trailing commas.
- Stripper commentaires bloc `/* ... */` avant parsing : `rawString.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)`.

### 4.3 UserDefaults — clés centralisées
- **Toutes clés dans `UDKey.swift`** — jamais string littérale dans le code.
- Clé de migration one-shot **retirée à version N+1** (commentaire dans UDKey.swift).

### 4.4 Appels réseau Nexus
- **Tous via `NexusRequestBuilder.makeRequest(...)`** (`Models/NexusRequestBuilder.swift`).
- Source unique : `apiBase`, `gameDomain`, `appName`, headers.
- Requêtes **sérielles** (pas de parallélisme) : rate limit.

### 4.5 Parsing des uniqueIds SMAPI
- Format `Author.ModName`. Centralisé `Extensions/SmapiUniqueId.swift` : `.smapiModName`, `.smapiAuthor`.

### 4.6 Concurrency / DispatchQueue
- **`weak self` obligatoire** dans toute closure passée à `DispatchQueue.global().async`.
- ViewModel + stores = `@MainActor @Observable` : **pas de `@Published`** (ne compile plus chez eux) — `var` stockée déjà suivie, état observable `private(set)`. Mutations d'état observé **toujours sur main thread**. Cinq types restent `ObservableObject` (`SmapiInstaller`, `BisectionRunner`, `KeybindScanService`, `LocalizationStore`, `ModListFilters`).
- **Méthode `@MainActor` appelée depuis fil de fond tue l'app** : mode Swift 6 vérifie à l'exécution. Ni gate ni tests ne le voient.
- **Structure mutable partagée entre scans** (cache manifests, registre) protégée par `NSLock` dédié. `scanMods()` tourne en background et peut tourner **en concurrence avec lui-même** (refresh + initial load, activation de profil vs refresh). Sans lock, subscript setter d'un `Dictionary` → `EXC_BAD_ACCESS` (crash confirmé juillet 2026 sur `manifestCache`).

### 4.7 `Process()` (sous-processus)
- Toujours **setter locale** `en_US_POSIX` : parsing indépendant de la langue système (unzip, etc.).

### 4.8 Force-unwrap
- **Interdit dans `CodeEditorView`**, à éviter partout. Préférer `guard let` / `if let`.

### 4.9 Symlink `/tmp` → `/private/tmp` (PIÈGE macOS)
- `FileManager.enumerator` rend chemins **résolus** (`/private/tmp/...`) même si root `/tmp/...`.
- **Toujours résoudre `fileURL.path`** via `resolvingSymlinksInPath()` avant `replacingOccurrences(of: resolvedRoot)`.
- Sinon chemin relatif corrompu (`private/.X/...` au lieu de `.X/...`).

### 4.10 `findExistingMod` — group-aware
- Chercher dans `children` des groupes (packs), en-têtes à `uniqueId` vide, pour détecter conflits sur mods installés en pack.

---

## 5. Architecture — points sensibles

### 5.1 `StarHubTHViewModel` = god-object
- ~10 000 lignes (10 027 au 2026-09-24). `scanMods()`, `performToggle`, `applyProfileToFilesystem`, `toggleAllMods`, `deleteMod`, `cleanDisabledMods`, `syncInstalledModRegistry` y vivent encore.
- Scan de `Mods/` (dont `parseModFolder`) dans `Models/ModScanner.swift`, détenu par VM (`private let scanner`).
- Refacto **en cours** (`docs/REFACTORING.md`) : état sort vers `StarHubTH/Stores/` (30 fichiers). Règle F1-T2 : fonctionnalité neuve naît dans son type (store ou type pur dans `Models/`), jamais dans VM. Taille VM verrouillée par cliquet.

### 5.2 Registre des mods installés
- Porté par `Stores/InstalledModRegistryStore.swift`. Clé UserDefaults `installedModRegistry` (blob JSON, ~90 Ko).
- Clé de secours `installedModRegistryBackup` + **restauration auto si corruption** + **reconstruction depuis disque**. ⚠️ Secours reçoit **mêmes octets** à chaque écriture : couvre clé illisible, pas retour à génération précédente.
- Cache mémoire (thread-safe, NSLock) — un decode par session au lieu de 100+ par scan.
- Sync fin de chaque `scanMods()` : capture installs par tous moyens (drag-drop, copie manuelle, installer).

### 5.3 Cache de manifests (DEPUIS juillet 2026)
- `manifestCache: [String: (mtime: Date, manifest: [String: Any])]` dans `ModScanner` (`Models/ModScanner.swift`), sous `manifestCacheLock`. Classe, pas valeur : deux scans concurrents partagent même cache.
- Key = chemin absolu du manifest.json. Hit = mtime identique → reuse JSON décodé.
- Rescan sans changement = ~N `stat()` + 0 decode.

### 5.4 Scanner — énumération à deux niveaux
- **Niveau 1 (top-level)** : `contentsOfDirectory` **sans** `skipsHiddenFiles` → voit les `.X`.
- Classification manuelle : `.X` = désactivé, `X` = activé, OS junk = skip.
- **Niveau 2 (sous-scan récursif)** : `enumerator` **avec** `.skipsHiddenFiles` → cache junk imbriqué (`.DS_Store`, `.git/`, `._Foo`).
- `relativePath` calculé **relativement au physicalRoot** (dossier entry), pas à `modsPath` — sinon point fuit dans `folderName`.

### 5.5 Drag-and-drop install
- **NE JAMAIS écraser** `config.json` ni `fr.json` d'un mod existant (conflit signalé).
- Nouveau mod → désactivé par défaut (`Mods/.X`).
- Update d'un mod **activé** → reste activé (`Mods/X`).

### 5.6 Backups
- `ModInstallBackupManager` (install) et `ModConfigBackupManager` (config) **distincts, non consolidés**.
- Rétention hybride 3 niveaux pour backups d'installation.
- `restoreBackup` restaure en **désactivé** (`Mods/.X`).

---

## 6. UI — contraintes fixes

- **Sidebar** : pas de barre de recherche. « Mod Updates » **toujours visible** (badge caché si 0).
- **Pages de liste** (`ModListView`, `LogsView`) : pattern `VStack(spacing: 0)` — header fixe + Divider + ScrollView + footer/pagination fixe.
- **Pagination** : 12 mods/page (`ModListView.pageSize`), saut de page direct.
- **Splash de lancement** : fenêtre séparée (`NSPanel`, `Views/LaunchSplashWindow.swift`), cover art, progression par phases, menus natifs masqués pendant chargement. Deux pièges AppKit ont tué l'app au lancement : `applicationShouldTerminateAfterLastWindowClosed` doit rendre `false`, et fenêtre principale masquée dans `applicationWillFinishLaunching`, pas `.onAppear`.

---

## 7. Git & release

- Travailler sur `main`.
- **Pousser uniquement sur demande explicite de l'utilisateur.** Fetch + rebase avant : d'autres sessions poussent aussi sur `main`.
- Commits : style conventional (`feat:`, `fix:`, `chore:`, `docs:`).
- `CHANGELOG.md` : Keep a Changelog. Section `[Unreleased]` **intégrée à la prochaine release, jamais supprimée**.
- Release : `release.py` bump version dans source + CHANGELOG. Bundle dans `bundles/`, préfixe `StarHubFR_v<version>.zip`.

---

## 8. Résumé — checklist avant de valider un changement

1. [ ] `python3 build_app.py` passe (compile + parité L10n).
2. [ ] `./run_tests.sh` passe (~3 400 tests).
3. [ ] Touché `en.json`/`fr.json` : parité clés + messages cohérents dans les deux langues.
4. [ ] Touché chemin disque de mod : `physicalFolderName`, pas `folderName`.
5. [ ] Nouveau code réseau : via `NexusRequestBuilder`.
6. [ ] Nouveau code asynchrone : `weak self` + mutations sur main ; aucune méthode `@MainActor` appelée depuis fil de fond.
7. [ ] Nouvelle fonctionnalité : store ou type pur, pas ViewModel (F1-T2).
8. [ ] Parsing de manifest : pas de `.allowFragments`, strip commentaires.
9. [ ] Énumération de fichiers : résoudre symlinks avant comparaison de chemins.
10. [ ] Touché URL, chemin d'API, en-tête ou constante de contrat externe :
       `python3 check_sources.py --offline` — **expliquer** l'écart, pas le
       taire (écart ≠ échec ; `--update` ne fait pas taire le script).
11. [ ] CHANGELOG à jour si changement visible par l'utilisateur.
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
