# Architecture de StarHubFR

Carte du code pour qui arrive sur le projet. Elle dit **où vit quoi** et **par où passe une action** ; les règles de contribution sont dans [`CONTRIBUTING.md`](../CONTRIBUTING.md), les pièges techniques dans [`AGENTS.md`](../AGENTS.md).

## Les documents, dans l'ordre de lecture

| Document | Ce qu'il apporte |
|---|---|
| [`CONTRIBUTING.md`](../CONTRIBUTING.md) | environnement, build, tests, règles du code, pull requests |
| **ce fichier** | la carte du code et des flux |
| [`docs/DOMAINE.md`](DOMAINE.md) | le vocabulaire métier : mod, pack, profil, sauvegarde, mod en pause — des mots qui n'ont pas le sens de l'amont |
| [`AGENTS.md`](../AGENTS.md) | conventions et pièges consolidés (section 4 surtout), commandes exactes |
| [`docs/SOURCES.md`](SOURCES.md) | tout ce qui vient de l'extérieur : API appelées, fichiers lus, code repris et sa licence |
| [`docs/REFACTORING.md`](REFACTORING.md) | la sortie progressive du ViewModel vers des magasins |
| [`docs/ROADMAP.md`](ROADMAP.md) | ce qui reste à faire ; ce qui est livré est dans [`docs/roadmap-archive.md`](roadmap-archive.md) |
| [`CHANGELOG.md`](../CHANGELOG.md) | ce qui a changé pour l'utilisateur, version par version |

Les `docs/audit-*.md` sont des relevés datés (mods décompilés, concurrents, audits de code) : ils expliquent un choix, ils ne sont pas des consignes.

## Vue d'ensemble

StarHubFR est une app SwiftUI pour macOS 14 et plus, sans projet Xcode. Elle agit sur trois endroits du disque :

- **le dossier `Mods/` du jeu**, qu'elle lit et modifie (installer, mettre en pause, mettre à jour) ;
- **son dossier de données**, `~/Library/Application Support/StarHubFR/` (sauvegardes, caches, profils, historiques) ;
- **le dossier de la sonde**, `~/.config/StardewValley/ModData/mrbabilo.StarHubFR.Probe/`, où le mod compagnon dépose ses mesures.

Elle interroge smapi.io, Nexus Mods (API v1 avec clé, GraphQL v2), GitHub (releases de SMAPI) et, si l'utilisateur les configure, une IA locale ou DeepL. Le détail de chaque contrat est dans [`docs/SOURCES.md`](SOURCES.md).

## Arborescence

```
StarHubTH/                  sources de l'app (le nom de l'amont est resté)
  StarHubTHApp.swift        point d'entrée, AppDelegate, fenêtre et menus
  StarHubTHViewModel.swift  l'ancien objet central, en cours de démontage
  Models/                   logique pure : types, analyseurs, règles (≈ 350 fichiers)
  Stores/                   état observable d'un domaine, un magasin par sujet (≈ 60)
  Views/                    écrans SwiftUI (≈ 120)
  Design/                   jetons de design (couleurs, tailles) côté UI
  Extensions/               petites extensions partagées
  *.swift (racine)          managers historiques : installation, sauvegardes, SMAPI, Nexus
  L10n*.swift               accès typé aux libellés
assets/
  en.json, fr.json          libellés de l'interface, source de vérité
  *.lproj/                  générés par build_app.py, jamais édités
companion/
  StarHubFR.Probe/          la sonde : un mod SMAPI en C# (.NET)
  StarHubFR.Probe.Tests/    ses tests (dotnet test)
Tests/                      tests Swift du cœur, un dossier par sujet
tools/                      scripts Python hors app (relevés, oracles)
build_app.py                compile l'app, lance les contrôles, embarque la sonde
check_standards.py          cliquet des conventions
check_sources.py            relevé des sources externes
release.py                  build de release et archive
```

## Les couches

### Le cœur (`Package.swift`)

`Package.swift` déclare une bibliothèque, `StarHubTHCore`, qui liste **fichier par fichier** les sources testables : presque tout `Models/`, une partie de `Stores/`, les managers racine (`ModZipInstaller`, `ModInstallBackupManager`, `SaveManager`…). C'est le seul code que `swift test` compile, donc le seul qui se teste.

Une règle protège cette frontière : `build_app.py` refuse qu'un fichier du cœur importe SwiftUI. Une logique qui doit être testée naît dans `Models/`, s'ajoute à `Package.swift` et reçoit ses tests dans `Tests/<Sujet>Tests/`.

### Les magasins (`Stores/`)

Un magasin est une classe `@Observable` qui porte l'état d'un domaine : `ScanStore` (le dernier scan de `Mods/`), `ProfileStore`, `ModUpdateStore`, `NexusAccountStore`, `TranslationHubStore`, `ProbePerformanceStore`, `KeybindFamilyStore`… Il lit et écrit ses fichiers dans le dossier de données, en délègue la logique à des types de `Models/`, et l'UI le lit directement.

Patron d'un fichier persisté (voir `ModGroupStore`) : un champ `version` ; un fichier illisible est mis de côté, jamais écrasé ; un fichier d'une version future se lit en lecture seule.

### Le ViewModel (`StarHubTHViewModel.swift`)

L'objet central de l'amont, environ 8 000 lignes. Il détient encore le scan, la bascule des mods, l'application d'un profil, la suppression, et il possède les magasins qu'il expose aux vues. **Aucune fonction nouvelle n'y entre** : elle naît dans son magasin ou son type pur, et le ViewModel ne fait que la brancher. Sa taille est verrouillée par le cliquet ; le plan de sortie est dans [`docs/REFACTORING.md`](REFACTORING.md).

### Les vues (`Views/`)

`MainView` porte la barre latérale et l'onglet courant ; chaque page est une vue (`ModListView`, `PerformanceView`, `ProfilesView`…) qui reçoit le ViewModel et lit ses magasins. La navigation entre pages passe par `NavigationStore` : une intention (« ouvrir Performances sur tel mod ») est posée dans un champ `pending…Focus` et consommée par la page d'arrivée, parce qu'un changement d'onglet remet à zéro les vues de détail.

## Les flux principaux

### Scanner `Mods/`

`ModScanner` (`Models/`) parcourt le premier niveau de `Mods/` sans masquer les dossiers cachés : `X` est un mod actif, `.X` un mod en pause. Il descend ensuite dans chaque dossier pour trouver les `manifest.json` (un pack en contient plusieurs) et garde un cache par date de modification : un nouveau scan sans changement ne relit aucun manifeste. Le résultat devient une liste de `ModItem`, publiée par `ScanStore` ; le registre des mods installés se synchronise à la fin.

Identité d'un mod : `ModItem.id` est son `folderName` **logique**, sans le point. C'est la clé de tous les fichiers persistés. Le chemin disque, lui, se construit toujours avec `physicalFolderName`.

### Mettre en pause, activer

Renommer `Mods/X` en `Mods/.X`, et l'inverse. SMAPI ignore les dossiers cachés. Rien ne se déplace hors de `Mods/`. Les mods livrés avec SMAPI restent actifs.

### Installer une archive

`ModZipInstaller` reconnaît le format à ses octets (jamais à l'extension), applique des limites de taille, refuse les chemins qui sortent du dossier, déduit la structure (mod seul ou pack) avec `ModZipStructure`, sauvegarde l'existant (`ModInstallBackupManager`) puis écrit. Le `config.json` et le `fr.json` d'un mod déjà installé ne sont jamais écrasés.

### Vérifier les mises à jour

Voie principale : `SmapiUpdateClient` envoie les manifestes à smapi.io, qui répond pour Nexus, CurseForge, ModDrop et GitHub. Filets : la liste de compatibilité de Pathoschild, le `metadata.json` local de SMAPI, puis Nexus directement. `ModUpdateStore` publie le résultat. La correspondance se fait par `UniqueID` du manifeste, jamais par identifiant Nexus (des mods distincts en partagent un).

### Traduire

L'onglet Traduction d'une fiche ouvre `TranslationDocument` (le `default.json` et le `fr.json` du mod, clé par clé). `TranslationTokenCheck` refuse un enregistrement qui perd un marqueur du jeu ; le glossaire vient des fichiers `.xnb` du jeu, lus par `XnbStringDictionaryReader` et un décodeur LZX transposé en Swift. L'IA locale (`LocalLLMClient`) n'accepte que des adresses locales.

### Mesurer les performances

La sonde (`companion/StarHubFR.Probe/`) est un mod SMAPI installé à la demande. En jeu, elle écrit des fichiers JSON et JSONL dans son dossier `ModData` (temps d'image, chargements, mémoire, carte des patches Harmony). `ProbeFiles` (`Models/`) nomme ces fichiers ; `ProbePerformanceStore` les relit et l'onglet Performances les compare. L'app ne parle jamais au jeu autrement que par ces fichiers et par les options qu'elle écrit pour la sonde.

`build_app.py` compile la sonde (`dotnet build -c Release`, avec les DLL du jeu installé) quand ses sources sont plus récentes que sa DLL, puis l'embarque dans `StarHubFR.app/Contents/Resources/Probe/`. Sans `dotnet` ni jeu, l'app se construit quand même et dit qu'elle ne peut pas installer la sonde. Chaque DLL livrée porte un numéro de version neuf dans `manifest.json`.

## Données sur disque

| Où | Quoi |
|---|---|
| `Mods/` du jeu | les mods ; `.X` = en pause |
| `~/Library/Application Support/StarHubFR/` | `Backups/` (installations, configs), caches Nexus, profils et leurs configs, historiques d'erreurs et de performances, glossaire, `mod_groups.json`, `keybind_families.json`… |
| UserDefaults `com.mrbabilo.StarHubFR` | réglages, registre des mods installés (avec une clé de secours) |
| Trousseau macOS | clé API Nexus, clé DeepL |
| `~/.config/StardewValley/ErrorLogs/SMAPI-latest.txt` | journal SMAPI, lu par le diagnostic |
| `~/.config/StardewValley/ModData/mrbabilo.StarHubFR.Probe/` | mesures de la sonde |

Les tests ne touchent jamais ces emplacements réels : chaque magasin ou manager testé reçoit un dossier temporaire.

## Outillage

| Script | Rôle |
|---|---|
| `build_app.py` | compile toutes les sources avec `swiftc` (incrémental), vérifie la parité `en`/`fr`, génère les `.lproj`, contrôle la frontière du cœur, lance `check_standards.py`, embarque la sonde et le CHANGELOG, signe ad hoc. `--whole-module` recompile tout ; `--gen-compile-commands` régénère seulement `compile_commands.json` pour SourceKit-LSP |
| `run_tests.sh` | `swift test` avec Xcode ; accepte les options de `swift test` (`--filter`) |
| `check_standards.py` | cliquet : échoue si un compteur dépasse `.standards-baseline.json` ; `--report` montre l'état |
| `check_sources.py` | compare l'état des sources externes à `.sources-baseline.json` ; un écart est une chose à regarder, pas une faute |
| `release.py` | incrémente le numéro de build, construit, archive dans `bundles/` |
| `tools/*.py` | relevés hors app (options GMCM des DLL, contextes d'écoute des touches) qui servent d'oracles aux lecteurs Swift |

La CI (`.github/workflows/ci.yml`, macOS 15, Xcode 16.4) compile le cœur, lance les tests et le cliquet. Elle ne compile pas l'app entière : `build_app.py` en local reste le contrôle d'un changement d'UI.
