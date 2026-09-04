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

## Sources à consulter — au-delà de ce fichier

Ce dépôt est travaillé par plusieurs IA, et le contexte n'est pas tout dans
`CLAUDE.md`. Dans l'ordre où ça sert :

- **`AGENTS.md`** — conventions et pièges consolidés (§4 surtout). Complémentaire
  de ce fichier, pas redondant.
- **`docs/DOMAINE.md`** — le vocabulaire métier. Obligatoire avant de toucher aux
  mods, à SMAPI, à Nexus, aux profils, aux sauvegardes ou aux traductions.
- **`docs/ROADMAP.md`** — l'état des tâches. ⚠️ Ses cases traînent derrière le
  code livré : vérifier `git log` avant de traiter une tâche « à faire ».
- **`.kilo/plans/`** — les plans écrits du temps de Kilo (installation par
  glisser-déposer, sauvegarde de config, bascule par préfixe point, comparaison
  StarHubFR/StarHubTH…). Ils portent le **raisonnement** derrière des choix
  encore en place, ce que le code ne dit pas. ⚠️ Ce sont des **archives**, pas
  des spécifications courantes : leurs cases ne valent rien et une partie a été
  livrée autrement. À lire pour le « pourquoi », jamais comme une consigne.
  Le reste de `.kilo/` (outillage, `node_modules`) reste ignoré.
- **`docs/superpowers/`** — specs et plans de travail récents. Locaux, gitignorés :
  absents d'un clone frais.

## Build & test — LIRE avant de valider un changement

Le build est **scindé en deux systèmes** ; vérifier lequel couvre le fichier touché.

- **Build réel de l'app** : `python3 build_app.py` — `swiftc` sur *tous* les
  `.swift` sous `StarHubTH/` (un seul module). C'est le **vrai gate** pour tout ce
  qui touche l'UI, le ViewModel, `SmapiInstaller`, `NexusUpdateChecker`, etc.
  `python` n'est **pas** dans le PATH → toujours `python3`.
  Depuis F2-T2, la compilation est **incrémentale** : ~2,4 s pour une
  modification isolée, ~30 s si la signature change dans le ViewModel, contre
  141,7 s auparavant. Le premier build après un `rm -rf .build` reprend 59 s.
  `--whole-module` rend l'ancien chemin, filet en cas de binaire douteux.
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
rencontrés. Pour les conventions plus larges, voir `AGENTS.md` §4 ; pour le
raisonnement derrière les choix anciens, `.kilo/plans/`.

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
- **`ForEach` avec `id: \.self` ou un index fait fuiter l'`@State`** d'une
  ligne vers une autre quand les données changent — identifier par une donnée
  stable (`Identifiable`), jamais par position.
- **Un `body` trop dense sature le type-checker** (compile en minutes,
  diagnostics absurdes) — découper en sous-vues / propriétés calculées.
- **~2 000 lignes de log : `List` a beach-ballé 8–10 s**, `LazyVStack` fixe ;
  une seule passe construit `logViews` — plusieurs propriétés calculées
  re-parcourent tout à chaque rendu.
- **Pas de surcharge `help(_:)` optionnelle dans ce SDK macOS** : passer par
  `helpIfPresent` (`StatStrip.swift`) — vérifier qu'une surcharge existe
  avant de l'invoquer.
- **Cycle de vie des fenêtres au lancement (splash `NSPanel`)** — deux pièges
  qui ont cassé l'app : `orderOut` sur la fenêtre principale vaut « dernière
  fenêtre fermée » (exiger `applicationShouldTerminateAfterLastWindowClosed`
  → `false`), et la masquer depuis `.onAppear` est trop tard (l'intercepter
  dans `applicationWillFinishLaunching`, observateur retiré dans `finish()`).
- **Un commit au blur (`onChange(of: focusState)`) meurt si la vue est
  remplacée par `.id(...)`** : le démontage arrive avant le blur — doubler
  d'un `onDisappear` committant le même draft, idempotent.
- **Changer d'onglet remet à `nil` les états de détail** (`MainView.swift:232`
  : `editingSave`, `viewingThaiMod`, `viewingSaveTimeline`,
  `editingModConfig`, `viewingModDetail`) — poser l'un d'eux puis changer
  `currentTab` est effacé avant le rendu. Faire porter l'intention par un
  `@Published` (`pending…Focus`), reconsommé **dans** le
  `.onChange(of: currentTab)` lui-même (patron B3-T4).

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
- **Un `Pipe` se lit avant `waitUntilExit()`** : un tube est borné (64 Ko sur
  macOS) — au-delà, l'enfant bloque sur son écriture et le parent sur son
  attente, sans crash ni journal (`hasTraversalEntry` figeait l'installation
  passé ~1 500 fichiers). Et tout `unzip` vers un dossier neuf passe `-o` :
  sans lui, une archive à chemins dupliqués pose une question sur un stdin
  qui n'existe pas dans une app GUI.
- **Un script lancé en tâche de fond ne doit jamais lire l'entrée standard** :
  son stdin est un tube qui ne se ferme jamais — une substitution de liste de
  boucle qui tourne en `cat` nu y bloque à l'infini (0 % CPU, zéro itération,
  pile bloquée dans `loop`, sonde Nexus 2026-08-31). Invoquer avec
  `< /dev/null` et lire les données d'un fichier explicite
  (`while IFS= read -r … < fichier`).

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
- **Encodage du manifest** : UTF-8 suffit, et **le BOM en tête (`EF BB BF`) ne
  pose aucun problème** — mesuré le 2026-09-04. Ce piège disait l'inverse ; il
  était faux. Sur macOS, `String(data:encoding:.utf8)` *retire* le BOM (premier
  scalaire rendu = `{`) et `JSONSerialization` l'accepte avec comme sans
  `.json5Allowed` — vérifié en compilant le cas, pas déduit. **142 des 1 096
  manifestes du parc en portent un**, tous lus correctement. Ce qui casserait
  vraiment, c'est un manifeste **hors** UTF-8 : `parseModFolder` abandonne alors
  en silence, sans même journaliser, et le mod paraît sans nom ni identifiant.
  Le parc n'en compte **aucun** — d'où l'absence de correctif.
- **Les i18n du parc ne sont pas toutes en UTF-8** : UTF-16 et UTF-32, LE et
  BE, existent réellement — passer par `I18nFileDecoder`, jamais
  `String(data:encoding:.utf8)` direct.
- **CRLF compte pour un seul `Character`** (`"a\r\nb"` = 3 caractères, pas 4) :
  découper par `Unicode.Scalar` ou tester `isNewline`, et garder une fixture
  CRLF dans les tests.
- **Clé écrite deux fois dans un i18n : le jeu retient la dernière** — le
  parseur déduplique en gardant la dernière (`I18nLenientParser`) ; garder la
  première diverge silencieusement du jeu.
- **Identifier un format binaire par ses octets, jamais par le nom ou
  l'extension** : 372 `.xnb` traités comme LZ4 étaient du LZX (marqueur
  `0x81`) — un nom d'archive ne dit rien de son contenu.
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
- **Le Nexus mod id n'est pas une clé d'identité** : des mods distincts le
  partagent (58 id partagés sur le parc ; l'id 8828 couvre 3 mods — indexer
  dessus a effacé les mises à jour de 3 mods). Toute clé par mod passe par
  l'`UniqueID`.
- **Une passe Nexus partielle (429, 503) fusionne avec le cache, elle ne le
  remplace pas** : un mod absent de la réponse n'est pas « à jour » — on
  conserve sa ligne précédente, seulement s'il est encore installé. Et le
  cache reste **à plat** : la liste affichée, consolidée par pack, ne doit
  jamais y être réécrite.
- **Requête smapi.io : `apiVersion` (et `gameVersion`) obligatoires.** Sans
  `apiVersion`, zéro suggestion revient ; une version mal formée vide le lot
  entier en silence.
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
- **Lire l'exit code du gate directement** : `python3 build_app.py | tail`
  rend le code de `tail` (vert même bloqué) ; et les diagnostics SourceKit
  juste après un build sont de la ré-indexation, pas des erreurs du code.
- **Ne pas éditer les sources pendant un gate** (8–12 min) : le build
  embarque des fichiers à moitié édités et le gate est perdu — attendre sa
  fin.
- **Les tests n'écrivent jamais dans le vrai Application Support** : 582
  exécutions ont pollué de vrais backups avant que les managers ne soient
  injectés — tout nouveau test d'un manager reçoit un dossier temporaire.

### UI

- **Sidebar : pas de barre de recherche**, et l'entrée "Mod Updates" doit
  rester visible en permanence (badge caché si 0 updates).
- **Pages de liste (`ModListView`, `LogsView`)** : patron `VStack(spacing: 0)`
  avec header fixe + `Divider` + `ScrollView` + footer/pagination fixe. Pas
  de `ScrollView` unique qui ferait tout défiler ensemble.
- **Toggle de mod = rename atomique préfixe point** : `Mods/X` ↔ `Mods/.X`.
  `ModItem.folderName` est **logique** (jamais de point). `physicalFolderName`
  est la version disque. Toute construction de chemin disque doit utiliser
  `physicalFolderName`. Le renommement invalide tout cache indexé par nom de
  dossier : déplacer la clé au toggle (`ModsFolderSizer` — le poids sinon
  disparaît à la bascule).
- **`.help()` sur un petit glyph ne s'affiche jamais** : macOS exige un survol
  d'environ 2 s entièrement dans la zone, et un glyph de 10 pt est plus petit
  que ce que le curseur peut tenir immobile — porter la cible à ~18×18
  (`frame` + `contentShape(.rect)`) avant le `.help`.

### Docs & roadmap

- **Les cases ROADMAP traînent derrière le code livré** : vérifier `git log`
  et le code avant de traiter une tâche « à faire » — des tâches livrées sont
  restées ouvertes plusieurs jours, deux fois en une semaine.

## Git

Travailler sur `main`. **Pousser uniquement quand l'utilisateur le demande.**
**Fetcher et rebaser avant de pousser** : d'autres sessions poussent aussi sur
`main`, et la CI GitHub juge chaque poussée.

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
