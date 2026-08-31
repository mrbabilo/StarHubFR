# CLAUDE.md — StarHubFR

Conventions partagées pour ce dépôt. Les *procédures* détaillées vivent dans les
skills (`.claude/skills/`) ; ce fichier ne fait qu'y pointer.

## Projet

- **StarHubFR** — gestionnaire de mods Stardew Valley pour macOS (SwiftUI, macOS 14+).
- Fork de **StarHubTH** (AppleBoiy). Le dossier source s'appelle encore `StarHubTH/`,
  mais le bundle produit est désormais `StarHubFR.app` (exécutable `StarHubFR`).
  Seul l'identifiant de bundle reste `com.appleboiy.StarHubTH` (Keychain/préférences).
- UI **bilingue** : anglais (`en`), français (`fr`). *(Le thaï comme langue d'UI a
  été retiré ; la fonctionnalité « Thai Translation Hub » — mods de traduction —
  reste, elle.)*

**Avant de toucher aux mods, à SMAPI, à Nexus, aux profils, aux sauvegardes ou aux
fichiers de traduction : lire `docs/DOMAINE.md`.** Il porte ce que le code ne dit
pas — notamment que « pack », « profil » et « sauvegarde » désignent ici autre
chose que chez l'upstream, et qu'un mod en pause est un dossier **préfixé par un
point** dans `Mods/`, pas un dossier déplacé.

## Build & test — LIRE avant de valider un changement

Le build est **scindé en deux systèmes** ; vérifier lequel couvre le fichier touché.

- **Build réel de l'app** : `python3 build_app.py` — `swiftc` brut sur *tous* les
  `.swift` sous `StarHubTH/` (un seul module). C'est le **vrai gate** pour tout ce
  qui touche l'UI, le ViewModel, `SmapiInstaller`, `NexusUpdateChecker`, etc.
  `python` n'est **pas** dans le PATH → toujours `python3`.
- **`swift build`** ne valide que le sous-ensemble Core du `Package.swift`
  (`ModItem`, les managers de backup, `SaveManager`, `L10n`, …) + ses tests.
- **Tests** : `./run_tests.sh` (lance `swift test` avec `DEVELOPER_DIR` sur Xcode).
  Peut échouer avec `no such module 'Testing'` si seuls les Command Line Tools sont
  actifs — c'est une **limite d'environnement, pas une régression**. Voir le skill
  `build-app` pour la vérification de logique quand `swift test` est inaccessible.
- **`compile_commands.json`** (racine, généré, gitignoré) alimente SourceKit-LSP
  pour l'autocomplétion sur *tous* les fichiers. Régénéré à chaque build ;
  rafraîchir seul avec `python3 build_app.py --gen-compile-commands`.
- **`check_standards.py`** — cliquet sur les conventions Swift, lancé par
  `build_app.py` après une compilation réussie. Il n'échoue que si un compteur
  **augmente** par rapport à `.standards-baseline.json` : le code viole
  massivement ces règles aujourd'hui, une barrière serait rouge dès le premier
  jour. Faire baisser un compteur puis `--update` pour resserrer ; `--report`
  pour voir l'état. Un ajout délibéré demande un `--update` explicite, visible
  dans le diff. `--skip-standards` débloque un build ponctuel.

**Ne jamais lancer l'app ni prendre de capture depuis un agent/sous-agent.** La
vérification GUI est déléguée à l'humain ; les agents valident par succès de build.

## Localisation

`assets/{en,fr}.json` sont la **source de vérité**. `build_app.py` valide la
**parité des clés** entre les deux (build en erreur sinon) et génère les
`assets/*.lproj/Localizable.strings`. Les clés sont référencées via `L10n.swift`.
→ Procédure complète : skill `localization`.

## Changelog & release

`CHANGELOG.md` suit le format **Keep a Changelog** ; incrémenté à chaque release
via `release.py`. → skill `release`.

## Traps — pièges techniques du projet

Synthèse des pièges qui **coûtent cher à retrouver** si on ne les a pas déjà
rencontrés. Pour les conventions plus larges, voir `AGENTS.md` §4. Les
corrections ponctuelles (avec leur commit) vivent dans la mémoire Kilo
(`corrections.md`).

### SwiftUI / AppKit

- **`CodeEditorView` : pas de force-unwrap.** `scrollView.documentView as! NSTextView`
  (makeNSView L.20, updateNSView L.35) remplacé par `guard let … as? NSTextView`.
  Un crash silencieux sur du contenu mal typé est inacceptable dans un éditeur
  de config.
- **Curseur main sur Markdown avec `textSelection(.enabled)`.** NSTextView
  réassertit le curseur I-beam en continu via ses `cursorRects`. Utiliser
  `onContinuousHover` (pas `onHover`) pour réassertir
  `NSCursor.pointingHand.set()` sur les liens.
- **macOS ne remplace pas une app ouverte lors de `open …`.** Une release locale
  ne prend effet qu'après fermeture complète (Cmd+Q) puis réouverture. Tester
  sur le bundle fraîchement compilé exige un kill préalable, sinon l'ancienne
  version reste en mémoire.
- **Éviter `textSelection(.enabled)` sur des zones non éditables** quand un
  contrôle interactif cohabite (lien, bouton dans le texte) : la sélection
  parasite le geste.

### Système de fichiers & Process

- **Symlink `/var/folders` → `/private/var/folders` sur macOS.**
  `FileManager.enumerator` retourne des URLs **résolues** (`/private/var/...`)
  même si la racine était `/var/...`. Toujours passer par
  `resolvingSymlinksInPath()` avant tout `replacingOccurrences(of: resolvedRoot)`
  sur un chemin calculé.
- **`Process()` doit forcer la locale `en_US_POSIX`.** Tout `Process` qui
  invoque `/usr/bin/unzip`, `unrar`, `unar`, `7z` et parse la sortie texte
  (notamment `uncompressedSize` dans `ModZipInstaller`) doit définir
  `process.environment = Self.cLocaleEnvironment`. Sinon, dates et tailles
  sont localisées et la regex casse sur les utilisateurs non-EN.
- **Pas de timeout sur `process.waitUntilExit()`** pour `unrar/unar/7z` —
  voir TODO `process_timeout_pending_todo` (reporte le fix, à ne pas dupliquer
  ailleurs).

### Concurrence

- **`scanMods()` peut tourner concurrentiellement avec lui-même** (refresh
  manuel + initial load, activation de profil en parallèle). Toute structure
  mutable partagée (cache `manifestCache`, registre installé) doit être
  protégée par un `NSLock` dédié. Le subscript setter d'un `Dictionary` Swift
  sans verrou cause un `EXC_BAD_ACCESS` (crash confirmé juillet 2026 sur
  `manifestCache`).
- **`weak self` obligatoire** dans toute closure passée à
  `DispatchQueue.global().async`. Toute mutation `@Published` doit rester sur
  le main thread.

### Modèles & parsing

- **Manifest JSON : pas de `.allowFragments` sans strip des commentaires
  bloc `/* … */` d'abord.** Un manifest DOIT être un objet ; accepter un
  scalaire masquerait un fichier corrompu. Stripper
  `/\*[\s\S]*?\*/` en `.regularExpression` avant parsing.
- **Encodage du manifest** : UTF-8 suffit, mais le BOM en tête (`EF BB BF`)
  fait échouer `String(data:encoding:.utf8)` silencieusement. Si un mod
  apparaît sans nom ou avec un nom bizarre, vérifier le BOM avant tout.
- **Nexus mod id depuis `UpdateKeys`** : `Nexus:191`, `Nexus: 191 ` (espaces),
  `Nexus:23169@SwimItems` (suffixe `@variant`) → tous parsables. Helper
  unique : `ModManifest.parseNexusId(fromUpdateKeys:)` (static, public, dans
  `StarHubTH/ZipModInfo.swift`). **Ne pas dupliquer** la logique dans le
  ViewModel ou ailleurs.
- **Nexus requests : un seul constructeur** via
  `NexusRequestBuilder.makeRequest(path:apiKey:)`. Source unique pour
  `apiBase`, `gameDomain`, headers `User-Agent`/`Application-Name`/
  `Application-Version`. Deux jeux d'en-têtes feraient voir deux clients
  distincts à Nexus.
- **Serialisation du registre** (`installedModRegistry` en UserDefaults) :
  backup auto avant écriture, restauration auto si corruption détectée, plus
  la reconstruction depuis le disque déjà existante. Les trois sont
  indépendants, tous requis.
- **Mise à jour d'un mod déjà activé** : préserver l'état activé après
  l'écrasement. Ne **jamais** écraser `config.json` ou `fr.json` d'un mod
  existant (drag-drop inclus).

### Build & release

- **`python3` uniquement**, jamais `python` (absent du PATH sur la machine
  de référence).
- **`DEVELOPER_DIR` obligatoire** pour `./run_tests.sh` : le framework
  Swift Testing (`import Testing`) requiert Xcode.app complet, pas les
  Command Line Tools. Sans `DEVELOPER_DIR` : `no such module 'Testing'` — c'est
  une **limite d'environnement**, pas une régression.
- **Parité des clés L10n obligatoire** : `en.json` et `fr.json` doivent
  contenir exactement les mêmes clés. `build_app.py` valide ça — un ajout
  dans un seul fichier fait échouer le build.
- **`check_standards.py` n'échoue qu'à l'**augmentation** d'un compteur**
  par rapport à `.standards-baseline.json`. Un `--update` explicite est
  requis pour assumer une nouvelle violation, visible dans le diff.

### UI

- **Sidebar : pas de barre de recherche**, et l'entrée "Mod Updates" doit
  rester visible en permanence (badge caché si 0 updates).
- **Pages de liste (`ModListView`, `LogsView`)** : patron `VStack(spacing: 0)`
  avec header fixe + `Divider` + `ScrollView` + footer/pagination fixe. Pas
  de `ScrollView` unique qui ferait tout défiler ensemble.
- **Toggle de mod = rename atomique préfixe point** : `Mods/X` ↔ `Mods/.X`.
  `ModItem.folderName` est **logique** (jamais de point). `physicalFolderName`
  est la version disque. Toute construction de chemin disque doit utiliser
  `physicalFolderName`.

## Git

Travailler sur `main`. **Pousser uniquement quand l'utilisateur le demande.**

Terminer les messages de commit par un trailer nommant le **modèle qui a
réellement écrit le commit** — jamais un nom figé :

- Claude : `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
  (ou `Claude Sonnet 5`, `Claude Haiku 4.5`… selon le modèle actif).
- GLM : `Co-Authored-By: GLM 5.3 <noreply@z.ai>`.

⚠️ Le dépôt est travaillé avec **plusieurs modèles**, dont GLM via `glm.sh`
(qui route Claude Code vers l'API z.ai : le modèle *actif* est alors GLM, quel
que soit l'alias `sonnet`/`opus` affiché). Vérifier quel modèle tourne avant de
signer.

L'historique antérieur au 2026-07-30 porte `Claude Sonnet 5` sur 167 commits,
y compris ceux d'autres modèles : ne pas s'y fier comme source de vérité.
