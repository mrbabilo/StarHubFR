# Audit Stardrop Native MacOS — synthèse concurrentielle

> **Date** : 2026-10-04.
> **Objet** : **Stardrop - Native MacOS** (Nexus [53356](https://www.nexusmods.com/stardewvalley/mods/53356)),
> dépôt `github.com/kxgcayh/Stardrop-NativeMac`, branche `development` @ `e68e005`
> (2026-10-04), tags `v1.10.4-macos` et `v1.11.0-macos`. C'est un **port macOS natif
> en Swift 6/SwiftUI du parent C# Stardrop** (`Floogen/Stardrop`) — le concurrent
> direct sur notre créneau : gestionnaire de mods Stardew natif SwiftUI, macOS 14+.
> **⚠️ Limite de licence, à lire avant toute envie de code** : le dépôt porte la
> **GPL-3.0** (`LICENSE` à la racine, héritée du parent Floogen/Stardrop, dont le
> code C# vit dans le même dépôt sous `Stardrop/`). La page Nexus afficherait
> « MIT » (rapporté en consigne d'audit, non revérifié ici) — **faire foi : le dépôt,
> pas la page**. Rien n'est repris en code ; ce document relève des **idées** et des
> **pièges** seulement. Toute reprise exigerait de trancher la licence d'abord.
> **Méthode** : clone lecture-seule `--depth 50` dans `/tmp` (supprimé après audit),
> lecture des 30 fichiers Swift (~5 600 lignes — le port est assez petit pour se lire
> en entier), recoupement avec `docs/ROADMAP.md` (axes A–I) et `docs/audit-stardrop.md`
> (le parent C#). Les chemins `StardropMac/…` désignent leur dépôt.
> **Suivi** : à enregistrer dans `docs/SOURCES.md` (clé `Stardrop-NativeMac`) au
> prochain relevé `check_sources.py` ; idées marquées `§audit-stardrop-nativemac` dans
> `ROADMAP.md`. **Rien n'est commité par cet audit.**

---

## 1. Ce qu'est Stardrop Native MacOS

La version native macOS du gestionnaire Stardrop, **écrite de zéro en SwiftUI** —
pas un habillage du code C#. Chiffres réels :

| | |
|---|---|
| Code Swift | **30 fichiers, ~5 601 lignes** (`StardropMac/Sources/StardropMac/`) |
| Plus gros fichiers | `ViewModels/AppState.swift` (1 132), `Views/ModTableView.swift` (826), `Views/MainView.swift` (427) |
| Dépendances | **zéro** (`Package.swift` : un executableTarget, swift-tools 5.9, `.macOS(.v14)`) |
| Tests | **aucun** (pas de cible test) |
| CI | **aucune pour le port** (les 10 workflows `.github/` ne couvrent que le C#) |
| Historique | **12 commits, tous du 2026-10-04** — le port est né et sorti en v1.11.0 le jour de l'audit |
| Parent | le C# v1.10.4 est présent dans le même dépôt (`Stardrop/`) |

**Verdict structurel** : un port **mince mais réel** — ~30× plus petit que StarHubFR
(~170 000 lignes), il reprend l'architecture conceptuelle du parent (symlinks,
`Settings.json`, profils) et réécrit toute l'UI. La comparaison avec le parent C#
(~2 850 lignes de code-behind pour la seule fenêtre principale) montre ce qui a été
**perdu** au passage (§3.9).

## 2. Architecture : ce qui est réutilisé du parent, ce qui est réécrit

**Réutilisé au niveau concept/format (pas de code) :**

- **Format de données du parent** : mêmes `Settings.json`, `Profiles/*.json`,
  `Separators/*.json` sous `~/Library/Application Support/Stardrop/Data/`
  (`Services/PathingService.swift:6-33`) — un utilisateur du C# Stardrop migre sans
  rien refaire, **clé Nexus comprise** (cf. SimpleObscure, §3.3).
- **Architecture « Selected Mods »** : au lancement, les mods activés sont **symlinkés**
  dans `Selected Mods/` et SMAPI est pointé dessus par `SMAPI_MODS_PATH`
  (`Services/SMAPILauncherService.swift:26-62`) — la même architecture junctions/symlinks
  que le parent, que `docs/audit-stardrop.md` §5 avait **écartée** pour StarHubFR
  (notre convention `X`/`.X` préfixe reste plus simple et ne peut pas casser un lien).
- **Protection des mods internes SMAPI** : `smapi.consolecommands`, `smapi.errorhandler`,
  `smapi.savebackup` toujours actifs, intouchables en masse, non supprimables
  (`Services/ModScannerService.swift:12-16`, `AppState.swift:248-249,509-510,1049`).

**Réécrit intégralement** : tout le reste (scan, smapi.io, Nexus, installation,
profils, UI). Le tableau du §4 compare point par point.

## 3. Fonctionnalités par axe

### 3.1 Analyse de mods

- Scan récursif, premier `manifest.json` par sous-dossier, dossiers cachés sautés
  (`ModScannerService.swift:43-73`).
- **Vrai JSON5** via `JSONDecoder.allowsJSON5` (`ModScannerService.swift:6-10`) —
  Foundation fait le travail que le parent C# confiait à un parseur pseudo-JSON.
  Égalité avec StarHubFR (notre vrai JSON5).
- Décodage **insensible à la casse des clés** via `DynamicCodingKey`
  (`Models/Manifest.swift:3-32`) — robustesse dont le parent était dépourvu.
- 🔴 **Un manifeste sans `UniqueID` reçoit un UUID aléatoire**
  (`Models/Manifest.swift:145` : `?? UUID().uuidString()`) : le mod apparaît, mais son
  identifiant **change à chaque scan** — les profils ne peuvent jamais le réactiver.
  À ne pas imiter : notre gestion des mods sans identifiant (111 sur le parc) est
  honnête (visibles, comptés, jamais inventés).
- **Aucun dédoublonnage** ni détection de doublon : deux dossiers au même `UniqueID`
  apparaissent deux fois (`ModScannerService.swift:18-41`). Pas d'équivalent de nos
  `ModDuplicateIndex`/`ModAnomaly`.
- `UpdateKeys` : tableau de **strings** ou string simple, mais **pas le tableau
  numérique** (`Manifest.swift:149-155`) — un `UpdateKeys: [541]` (que le parent
  normalisait via `ModKeyConverter.cs`) perd ses clés en silence.

### 3.2 Activation / pause

- Pause = **absence de symlink** dans `Selected Mods/`, les dossiers ne bougent jamais
  (contrairement à notre préfixe `.` : chez eux, un mod en pause reste visible dans la
  liste). Point de coexistence : leur scan saute les dossiers cachés
  (`skipsHiddenFiles`), donc **un parc StarHubFR pointé tel quel masquerait tous les
  mods en pause `.Pack`** — à documenter dans le GUIDE si on croise les deux outils.
- `hasUpdate`, `isCoreSMAPI`, `nexusModId` (préfixe `nexus:`, espaces tolérés) vivent
  dans `Models/Mod.swift:27-57`.

### 3.3 Intégration Nexus

- `Services/NexusService.swift` : `users/validate.json` (nom, is_premium), liste des
  endorsements filtrée Stardew Valley, **endorse/abstain POST avec typologie d'erreurs
  propre** (`isOwnMod`, `tooSoonAfterDownload`, `notDownloadedMod` —
  `NexusService.swift:112-156`). C'est le **seul write-op Nexus** du port.
- **Pas de téléchargement** (aucun `download_link`, aucun CDN, aucun GraphQL, pas de
  virus scan, pas d'affichage de quota, pas de `Retry-After`) : le bouton
  « Download Update » de l'inspecteur ouvre le **navigateur**
  (`Views/InspectorView.swift:135-141`).
- 🔴 **`nxm://` déclaré mais jamais câblé** : le schéma est dans l'`Info.plist`
  généré (`build-mac-app.sh`, `CFBundleURLTypes`) et **aucun handler n'existe**
  (zéro occurrence de `nxm` dans les sources). Cliquer un lien nxm lance l'app sans
  effet. Le parent l'avait désactivé sur macOS pour la même raison ; notre câblage
  Launch Services/`CFBundleURLTypes` + `handleNxmURL` reste devant.
- Clé stockée par **SimpleObscure porté à l'identique** : AES-256-CBC dont clé et IV
  vivent **en clair à côté du ciphertext** dans `Cache/Notion.json`
  (`Services/SimpleObscureService.swift:80-135`) — la faiblesse documentée du parent
  (`audit-stardrop.md` §5), conservée **volontairement** pour la compatibilité de
  format. Notre Trousseau reste devant ; leur choix est cohérent avec leur but
  (migrer les utilisateurs du C#).

### 3.4 smapi.io — mise à jour des mods

- `POST https://smapi.io/api/v3.0/mods` avec `includeExtendedMetadata: true`
  (`Services/ModUpdateService.swift:98-138`) — même endpoint que le parent.
- 🔴 **La moitié de la réponse est jetée** : le décodeur ne lit que `Id` et
  `SuggestedUpdate` (`ModEntry`, `ModUpdateService.swift:62-93`). Le bloc `Metadata`
  — **statuts de compatibilité, unofficial, URLs** — est ignoré. Le port n'a donc
  **aucune carte de compatibilité**, là où notre A2 (livrée) lit les statuts et les
  unofficial. Leur `hasUpdate` est une **comparaison de chaînes**
  (`Models/Mod.swift:50-53` : `suggested != manifest.version`) — un `v1.4.1` ou une
  prérelease déclenche un faux « mise à jour » ; notre SemVer reste devant.
- 🔴 **Versions d'environnement codées en dur** : si `GameDetails` est absent des
  settings, l'app envoie `apiVersion: "4.1.8"` et `gameVersion: "1.6.14"` **inventés**
  (`ModUpdateService.swift:112-118`). Or `GameDetails` n'est **jamais écrit par
  l'app** (aucune écriture dans les sources ; seul le C# Stardrop, qui partage le
  dossier de données, le remplit en parsant `SMAPI-latest.txt`). Un utilisateur
  qui n'a que le port interroge smapi.io avec des valeurs fausses — exactement le
  piège « smapi.io juge sans la version installée » documenté de notre côté
  (apiVersion réelle exigée, versions tirées du log).
- 🔴 **Non-200 → liste vide en silence** (`ModUpdateService.swift:132-134`) — le lot
  disparaît sans message ; et comme ils soumettent la version brute du manifeste
  comme `installedVersion`, une version malformée **vide le lot** (piège que nous
  avons déjà subi et corrigé). Pas de TTL ni de cache (appel manuel ⌘U seulement).

### 3.5 Installation d'archives

- `Services/ModInstallerService.swift` : zip → `/usr/bin/ditto -xk`, tar/gz/bz2/xz →
  `/usr/bin/tar`, 7z/rar → `7z`/`unrar` cherchés dans `/opt/homebrew/bin` etc.
  (`findExecutable`, `:245-258`), **avec repli tar pour .rar/.7z sans outil** —
  c'est-à-dire un **échec garanti** déguisé en message d'extraction obscur
  (`:192-205`). Détection **par extension, pas par octets** — notre règle « croire
  les octets » reste devant (un `.zip` renommé échoue chez eux avec le message de
  l'outil, pas une explication).
- Multi-manifest par archive : **oui**, via re-scan récursif du dossier temporaire
  (`:94-98`) — les content packs multiples passent.
- `__MACOSX/` et `.DS_Store` nettoyés (`:223-236`). **`config.json` de l'utilisateur
  préservé à la mise à jour** (copié dans la nouvelle version avant remplacement,
  `:146-152`) — détail bien vu.
- 🔴 **Mise à jour non atomique** : `removeItem` de l'ancien dossier **avant**
  `copyItem` du nouveau (`:155-163`) — un échec de copie entre les deux laisse
  **le mod supprimé** (pas de corbeille à l'update ; la corbeille n'existe que pour
  la suppression manuelle). Notre backup avant update (`Backups/ModInstalls/`)
  reste devant.
- Les champs custom du parent `DeleteOldVersion`/`UpdateCautionMessage` sont
  **perdus** dans le port (absents du modèle `Manifest.swift`) — régression vs parent.
- Pas de repli sur permissions (`X7` non rejoué) — le remove+copy l'évite par
  accident, comme le parent.

### 3.6 Suppression et dépendances

- Suppression à la **corbeille** (`trashItem`, repli `removeItem`,
  `AppState.swift:1115-1123`) avec nettoyage des références dans **tous** les profils
  et séparateurs (`:1094-1112`) — hygiène correcte.
- **Avertissement dépendants avant suppression** : les mods **activés** qui déclarent
  la cible en `isRequired` ou `contentPackFor` sont listés dans la confirmation
  (`AppState.findEnabledDependents`, `:1038-1046` + `Models/ModDeletionPrompt.swift`).
- L'inspecteur marque les dépendances absentes (« Missing ») et rend le mod parent
  cliquable (`Views/InspectorView.swift:167-263,387-397`), avec cas spécial
  `Pathoschild.SMAPI`. **Mais** : pas de comparaison de `MinimumVersion` (dépendance
  présente trop ancienne = « installée »), et **pas de cascade d'activation** —
  activer un mod n'active pas ses dépendances (le parent avait `EnableRequirements`
  récursif ; perdu au port ; nous l'avons en opt-in livré).

### 3.7 Profils, lancement, éditeur de config

- Profils basiques : création/duplication/renommage/protection du `Default`
  (`Services/ProfileService.swift`). **Nom de profil = nom de fichier sans
  sanitisation** (`:54`), renommage non transactionnel (delete puis write). Le champ
  `notes: [String]` du modèle est **mort** (jamais décodé, jamais encodé,
  `Models/Profile.swift:47,76-77`) — pas d'équivalent de nos notes B3-T6.
- Lancement SMAPI : `Process` direct sur `StardewModdingAPI` (le shim du jeu),
  `currentDirectoryURL` = jeu, **environnement hérité puis surchargé**
  (`SMAPILauncherService.swift:60-62`) — la règle « ne jamais remplacer
  l'environnement d'un enfant » est respectée par construction, et le lancement direct
  du shim évite la fenêtre Terminal (notre `SMAPI_NO_TERMINAL` devient inutile avec
  cette approche). Les échecs de `createSymbolicLink` sont avalés (`try?`, `:44`) —
  un lien raté = un mod absent de la session **en silence**.
- Éditeur de `config.json` : un `TextEditor` brut qui écrit sans aucune validation
  (`Views/ConfigEditorSheet.swift:66-71`). Le README affirme « JSON syntax validation
  before saving » — **c'est faux** : aucun `JSONSerialization` dans le fichier.
  Écart README/code à retenir contre eux ; notre éditeur typé (B3-T5, arbres
  ConfigJSONTree) reste très devant.

### 3.8 Séparateurs et multi-sélection (le vrai neuf du port)

- **Séparateurs visuels** (`Models/ModSeparator.swift`, `Views/ModTableView.swift:178-340`) :
  bannières pliables à la Mod Organizer 2, réordonnables, déplacer un mod entre
  groupes, activer/désactiver tout un groupe, **auto-génération depuis la structure
  de sous-dossiers** (`AppState.autoGenerateSeparatorsFromFolders`, `:834-859` —
  reconnaît le préfixe `[MODS] - `).
- **Multi-sélection clavier complète** : ⇧clic/⇧↑↓ pour les plages, ⌘clic pour
  ajouter/retirer, ⌘A, bascule **Espace** (si un seul désactivé → tout activer),
  navigation ↑↓ (`AppState.swift:185-400`). Le README documente la garde de focus
  (la saisie ne déclenche pas la bascule) — le piège SwiftUI que nous connaissons.

### 3.9 Ce que le port n'a pas (tout le reste)

Aucun diagnostic de log SMAPI (il ouvre `SMAPI-latest.txt` dans l'app par défaut),
pas de bissection, pas de réparation de dossier/manifeste, pas de détection
d'anomalies, pas de sauvegardes de jeu, pas de traductions (UI anglaise seule,
zéro `NSLocalizedString`), pas de hub, pas de sonde ni télémétrie, pas de
téléchargement, pas de nxm câblé, pas de logs propres (`print` vers stdout ; le
`Logs/Stardrop.log` du README n'est écrit par personne), pas de Stats de jeu,
pas de comptes de vitesse, pas de conflits inter-mods. **Tout l'avantage
différenciant de StarHubFR tient encore.**

## 4. Positionnement StarHubFR vs Stardrop Native MacOS

| Domaine | StarHubFR | Stardrop-NativeMac |
|---|---|---|
| Diagnostic de log SMAPI | ✅ Carte de santé, repliement, santé par mod | ❌ ouvre le fichier |
| Compatibilité smapi.io (statuts, unofficial) | ✅ A2 livrée | ❌ metadata ignorée |
| Versions jeu/SMAPI réelles | ✅ lues du log | 🔴 codées en dur / Settings du C# |
| Téléchargement in-app + `nxm://` | ✅ | ❌ (schéma déclaré, non câblé) |
| Endorsement Nexus | ❌ | ✅ (+ typologie d'erreurs) |
| Séparateurs/groupes visuels | ❌ | ✅ (idée → I-T21) |
| Multi-sélection fine + Espace | partiel (tout/rien) | ✅ (idée → I-T20) |
| Protection mods internes SMAPI | ❌ (accueil seulement, `CoreModSlot`) | ✅ (idée → A1-T12) |
| Profils | ✅ B3 livré (configs par profil, notes) | 🟡 basiques, notes mortes |
| Sauvegardes de jeu | ✅ | ❌ |
| Traduction FR / hub | ✅ axe C | ❌ UI anglaise seule |
| Perf mesurée / sonde | ✅ D4/D5 | ❌ (scan synchrone au thread principal) |
| Doublons / anomalies | ✅ | ❌ |
| JSON5 manifeste | ✅ | ✅ (Foundation) |
| Corbeille à la suppression | ✅ | ✅ |
| Backup avant mise à jour | ✅ | 🔴 remove-then-copy non atomique |
| Signature / notarisation | 🟡 E2-T3 ouvert | ❌ DMG non signé (Gatekeeper) |
| Clé Nexus | ✅ Trousseau | 🔴 AES + clé/IV en clair à côté |
| Licence | — | ⚠ GPL-3.0 (idées seules) |

**Lecture** : le port ne menace pas la profondeur de StarHubFR — il ne fait ni
diagnostic, ni téléchargement, ni traduction, et son usage de smapi.io est **plus
pauvre que celui du parent C#** qu'il remplace. Il menace sur **trois autres plans** :
(1) la **marque Stardrop** et sa base d'utilisateurs C# à migrer en un clic (mêmes
fichiers de données, clé comprise) ; (2) le **nativisme** — pas de .NET, DMG de 6 Mo,
ce que notre axe E n'a pas encore livré ; (3) la **vitesse** — v1.10.4 → v1.11.0 et
quatre features (install, endorsements, multi-sélection, suppression) en une journée.
C'est le premier vrai concurrent natif SwiftUI sur notre créneau exact ; sa faiblesse
actuelle (qualité §5, zéro test, zéro CI, non signé) laisse une fenêtre, pas une
garantie.

## 5. Qualité du port — défauts et pièges relevés

| # | Défaut | Où | Pourquoi ça compte |
|---|---|---|---|
| 1 | `nxm://` dans l'Info.plist, **aucun handler** | `build-mac-app.sh`, sources | promesse morte ; la variante Objective-C d'un même geste nous a coûté un gate |
| 2 | Versions `apiVersion`/`gameVersion` **codées en dur** envoyées à smapi.io | `ModUpdateService.swift:114-115` | verdicts calculés sur des versions fausses ; le lot peut vide en silence (versions malformées soumises telles quelles) |
| 3 | Metadata smapi.io **jetée** (statuts, unofficial) | `ModUpdateService.swift:62-93` | le port perd la meilleure moitié de l'API que le parent exploitait |
| 4 | `hasUpdate` = comparaison de chaînes | `Models/Mod.swift:50-53` | faux positifs (`v1.4.1`, préreleases) |
| 5 | UUID **aléatoire** pour manifeste sans `UniqueID` | `Models/Manifest.swift:145` | identifiant instable : profil incapable de réactiver le mod |
| 6 | Update **non atomique** (remove avant copy, sans corbeille) | `ModInstallerService.swift:155-163` | échec de copie = mod perdu |
| 7 | Symlinks d'activation avalés par `try?` | `SMAPILauncherService.swift:44` | mod absent de la session en silence |
| 8 | Éditeur de config sans validation, README mensonger | `ConfigEditorSheet.swift:66-71` vs README | un JSON cassé écrit tel quel (le jeu, lui, juge strict) |
| 9 | `.rar`/`.7z` sans outil → repli `tar` = échec garanti | `ModInstallerService.swift:188-205` | message obscur, jamais de cause |
| 10 | Détection d'archive par **extension** | `ModInstallerService.swift:23-25,72-76` | nos règles « croire les octets » (X4/X5) restent la bonne école |
| 11 | Pas de cascade d'activation des dépendances, pas de `MinimumVersion` comparée | `AppState.swift` (toggle*), `InspectorView.swift:387-397` | régression vs parent ; activer un mod orphelin de ses deps est autorisé sans avertir |
| 12 | Scan **synchrone au thread principal** à l'init | `AppState.init` → `refreshMods` | sur un parc type 900+ mods, gel au lancement (règle `@MainActor` du dépôt) |
| 13 | Binaire **non signé, mono-architecture** (`swift build` = arch hôte), README prétend arm64+x86_64 | `build-mac-app.sh`, `build-dmg.sh` (aucun `lipo`, aucun `codesign`) | Gatekeeper bloquera le DMG ; la promesse universelle n'est pas tenue par les scripts |
| 14 | `GameDetails` jamais écrit, jamais saisi dans l'UI | sources (lecture seule partout) | le panneau « System Info » reste vide sans le C# Stardrop à côté |
| 15 | Doublons `UniqueID` affichés deux fois, sans alerte | `ModScannerService.swift:18-41` | silence là où nous levons une anomalie |

Rien de tout cela n'est à reprendre — c'est la **liste des pièges que nos propres
audits ont déjà clos**, vue chez le concurrent : bonne nouvelle, notre école
marche ; mauvaise nouvelle pour eux, la qualité de v1.11.0 est celle d'une
démonstration d'un jour.

## 6. Idées retenues → `ROADMAP.md` (marque `§audit-stardrop-nativemac`)

Ajoutées aux axes (aucune case cochée ; détails dans `ROADMAP.md`) :

| Idée | Renvoi | Effort | Pourquoi |
|---|---|---|---|
| Multi-sélection fine (⇧ plages, ⌘ items, ⌘A) + bascule **Espace** sur la sélection | **I-T20** | S | manipulation en masse à l'échelle du parc (966 mods) ; le parent l'avait suggérée (`audit-stardrop.md` §4.3), le port la démontre complète |
| Groupes/séparateurs pliables dans la liste, activer/désactiver par groupe, auto-génération depuis les sous-dossiers `[MODS] - …` | **I-T21** | M | organisation visuelle que nos profils ne couvrent pas (un profil = un état, un groupe = un rangement) |
| Protéger les 3 mods internes SMAPI dans les opérations en masse (toujours actifs, hors « désactiver tout », non supprimables, hors compte) | **A1-T12** | S | validait `audit-stardrop.md` §3.6 (« nettoyage quasi gratuit »), jamais pris ; le port le fait simplement |
| Endorsement/abstention depuis la fiche mod (avec leur typologie d'erreurs comme référence) | **A3-T8** | S | faible priorité ; seul write-op Nexus utile que nous n'avons pas |

**Références sans item** (à relire au moment de E2-T3) : leur `build-dmg.sh`
(fond généré par script Swift + mise en page Finder + SHA256) est un bon canevas de
packaging DMG **sans signature** — à prendre comme plancher, pas comme cible (nous
restons sur signature/notarisation/Sentinel). La compatibilité de format avec le C#
Stardrop (§2) rappelle l'intérêt d'un §migration dans le GUIDE (E2-T2) : lire les
données d'un autre gestionnaire à l'arrivée, comme nous l'avons fait pour le
domaine/Trousseau du fork.

## 7. À NE PAS porter

| Piste | Décision | Raison |
|---|---|---|
| Architecture `Selected Mods/` + `SMAPI_MODS_PATH` | **Écartée (encore)** | déjà rejetée au §5 d'`audit-stardrop.md` ; sur macOS en plus, un symlink avalé en silence = un mod absent de la session (défaut #7) |
| SimpleObscure (AES + clé/IV à côté) | **Écarté** | obfuscation, pas sécurité ; le Trousseau reste devant |
| `hasUpdate` par comparaison de chaînes | **Écarté** | notre SemVer est correct ; reprendre ceci serait une régression |
| UUID inventé pour `UniqueID` absent | **Écarté** | casse le lien profil ↔ mod ; notre gestion est plus honnête |
| Repli `tar` pour `.rar`/`.7z` | **Écarté** | échec garanti déguisé ; notre détection par octets au moins nomme la cause |
| Update remove-then-copy | **Écarté** | notre backup avant update garantit le retour arrière |

## 8. Limites de l'audit

- **Lecture statique** : aucune exécution du port (consigne du dépôt : ni app ni
  build lancés par un agent). Les comportements sont lus dans le code.
- **Le port a un jour** : v1.11.0 date du 2026-10-04 comme cet audit ; les défauts
  §5 peuvent disparaître vite (l'auteur commitait encore l'heure du clone). Une
  relecture dans un ou deux mois vaut le coût si l'app prend.
- **Recoupement asymétrique** : le port a été lu en entier ; StarHubFR a été vérifié
  par `grep` ciblés (`CoreModSlot`, multi-sélection, dépendances, corbeille), pas relu.
- **Écart de licence Nexus non revérifié** : le « MIT » affiché sur la page Nexus est
  pris de la consigne d'audit ; le dépôt, lui, est bien GPL-3.0.

## 9. Index des fichiers StardropMac les plus pertinents

Tous sous `StardropMac/Sources/StardropMac/` :

- **Analyse de mods** : `Models/Manifest.swift` (décodage insensible à la casse),
  `Models/Mod.swift`, `Services/ModScannerService.swift` (JSON5, core mods).
- **Updates** : `Services/ModUpdateService.swift` (smapi.io partiel).
- **Nexus** : `Services/NexusService.swift` (validate, endorsements),
  `Services/SimpleObscureService.swift` (port de la clé obscurcie),
  `Views/NexusAccountSheet.swift`.
- **Installation/suppression** : `Services/ModInstallerService.swift` (ditto/tar/7z),
  `ViewModels/AppState.swift:941-1132` (install, suppression, dépendants).
- **Lancement** : `Services/SMAPILauncherService.swift` (symlinks + `SMAPI_MODS_PATH`).
- **Profils/séparateurs** : `Models/Profile.swift`, `Services/ProfileService.swift`,
  `Models/ModSeparator.swift`, `Services/SeparatorService.swift`,
  `Views/ModTableView.swift`, `Views/SidebarView.swift`.
- **Distribution** : `build-mac-app.sh` (bundle + Info.plist + schéma nxm),
  `build-dmg.sh` (DMG stylé + SHA256, non signé).
