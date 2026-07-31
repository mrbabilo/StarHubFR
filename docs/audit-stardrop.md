# Audit Stardop — synthèse concurrentielle

> **Date** : 2026-07-31.
> **Objet** : analyser le code de **Stardop** (`github.com/Floogen/Stardrop`, C# / Avalonia)
> pour cataloguer ses fonctionnalités d'analyse de mods et identifier ce qui manque à
> StarHubFR ou mérite d'être amélioré.
> **Méthode** : clonage lecture-seule du dépôt, dispatch de 4 analyses parallèles (analyse
> de mods, intégration Nexus, profils, fonctionnalités transverses), recoupement avec le
> code local de StarHubFR et la roadmap (`docs/ROADMAP.md`). Les chemins `Stardrop/…`
> ci-dessous désignent le code source de Stardop (vérifiables après `git clone`).
> **Suivi** : ce document est cité par la roadmap. Les tâches qu'il inspire portent la
> marque `§audit-stardrop` dans `ROADMAP.md`.

---

## 1. Ce qu'est Stardop

Gestionnaire de mods Stardew Valley **cross-platform** (Windows / macOS / Linux), en C# avec
le framework Avalonia. C'est le gestionnaire le plus mature de l'écosystème (~2850 lignes de
code-behind dans `MainWindow.axaml.cs`). Points forts reconnus : intégration Nexus profonde,
orchestration OS (protocole `nxm://`, auto-update, junctions/symlinks), richesse de gestion
des profils. 14 langues d'UI (couverture inégale, aucun garde-fou de parité au build).

---

## 2. La trouvaille clé — smapi.io comme source de compatibilité

Stardop interroge l'**API live `https://smapi.io/api/v3.0/mods`**
(`Stardrop/Utilities/External/SMAPI.cs:93-160`) avec `IncludeExtendedMetadata: true`. C'est la
**source que SMAPI lui-même utilise au démarrage** pour vérifier les mods.

Pour chaque mod, la réponse (`Stardrop/Models/SMAPI/Web/ModEntry.cs`) renvoie :

- `SuggestedUpdate` — version recommandée + URL (`ModEntryVersion`).
- `Metadata.CompatibilityStatus` — enum `WikiCompatibilityStatus` :
  `Unknown | Ok | Optional | Unofficial | Workaround | Broken | Abandoned | Obsolete`.
- `Metadata.Unofficial` — version + URL de **mise à jour non officielle** (pour mods
  abandonnés pris en charge par un tiers).
- `Metadata.Main` / `CustomUrl` — page officielle du mod.
- `Metadata.Errors[]` — erreurs renvoyées par smapi.io pour ce mod.

### Pourquoi ça change la roadmap

La roadmap **A2** prévoyait d'utiliser la liste **statique** `Pathoschild/SmapiCompatibilityList`
(`mods.jsonc`). Or :

1. **smapi.io est plus riche** que `mods.jsonc` : elle ajoute la mise à jour *suggérée* et
   l'URL de mise à jour *non officielle*, absentes du dump statique.
2. **smapi.io est plus fraîche** : c'est la donnée que voit SMAPI au démarrage.
3. **mods.jsonc est un dump** de `smapi.io/mods` — l'utiliser comme source primaire, c'est
   prendre une copie figée d'une source vivante.

**Recommandation** : A2 interroge `smapi.io` comme source primaire, `mods.jsonc` servant de
**fallback hors-ligne** (et de source pour `brokeIn` si smapi.io ne le fournit pas). Les DTO
(`ModSearchEntry`, `ModEntry`, `ModEntryMetadata`, `ModSearchData`) sont de simples records
JSON, directement portables en Swift. Aucune librairie GraphQL ou lourde nécessaire : un POST
JSON avec la query en body suffit.

> ⚠️ Réserve conservée : `smapi.io/mods` annonce lui-même ne plus être mis à jour
> exhaustivement, et son avenir est incertain. À traiter en **complément** au diagnostic de
> log SMAPI (déjà livré côté StarHubFR), jamais comme source unique de vérité.

---

## 3. Catalogue des fonctionnalités d'analyse de mods

### 3.1 Parsing des manifests

- **Tolérance** : `AllowTrailingCommas` + commentaires `//` via `System.Text.Json`
  (`Stardrop/Utilities/Internal/ManifestParser.cs:23-35`). **Ce n'est pas du vrai JSON5**
  (pas de guillemets simples, pas de clés non quotées). Repli sale : supprimer les `\r\n` en
  cas d'échec.
- **Conversion `UpdateKeys` numérique** : un manifest peut écrire `UpdateKeys: [541]` au lieu
  de `["Nexus:541"]` ; `ModKeyConverter.cs:10-37` normalise à la désérialisation.
- **Écart StarHubFR** : StarHubFR fait du **vrai JSON5** (commits `49325dc`, `14394ca`) →
  supériorité nette. Vérifier la robustesse du parser sur un `UpdateKeys` tableau d'entiers.

### 3.2 Scanner et hydratation des mods

- **Découverte** récursive, premier `manifest.json` par sous-dossier
  (`MainWindowViewModel.cs:237-261`). Ignore les dossiers cachés (`.smapi-tmp`, etc.) si
  `IgnoreHiddenFolders` est activé.
- **Hydratation** (`DiscoverMods`, `MainWindowViewModel.cs:391-530`) : parse → construit un
  `Mod` → ajoute une dépendance synthétique vers `ContentPackFor.UniqueID` (content packs) →
  parcourt `Dependencies` → résout les noms depuis `Keys.json`.
- **Dédoublonnage par UniqueID** : silencieux — la version la plus récente gagne, l'autre est
  ignorée **sans alerter l'utilisateur** (`:487-496`).
- **Écart** : StarHubFR scanne déjà `Mods/` et détecte les content packs. **Ne pas imiter**
  le dédoublonnage silencieux (comportement trompeur).

### 3.3 Résolution de dépendances

- **Marquage `IsMissing`** : une dépendance requise absente **ou présente en version trop
  ancienne** est marquée manquante (`EvaluateRequirements`, `MainWindowViewModel.cs:548-584`),
  via comparaison SemVer sur `MinimumVersion`.
- **Cascade d'activation** : `EnableRequirements`/`DisableRequirements`
  (`MainWindow.axaml.cs:2235-2267`) est **récursive** — activer un mod active toutes ses
  dépendances ; désactiver un mod désactive en cascade tout ce qui en dépend.
- **Lien cliquable** : `ManifestDependency.GenericLink` génère `https://smapi.io/mods#Nom`
  par dépendance manquante (espace → `_`).
- **Écart** : StarHubFR a **déjà** la cascade récursive (flag opt-in, `StarHubTHViewModel.swift:472`
  + `:1711`) et l'arbre de dépendances. Probablement **manquants** : la marque « version trop
  ancienne = manquante », et le lien cliquable `smapi.io/mods#Nom` par dépendance absente.

### 3.4 smapi.io — cache de compatibilité et de noms

Outre l'appel live (§2), Stardop maintient deux caches persistants :

- **`Versions.json`** (`UpdateCache`, `Pathing.cs:79`) : `SuggestedVersion` + `Status` +
  lien par mod, pour un affichage instantané au démarrage sans rappeler smapi.io.
- **`Keys.json`** (`ModKeyInfo`, `Pathing.cs:84`) : `UniqueId → Nom + PageUrl`. Alimenté à la
  fin d'un check smapi.io (`MainWindow.axaml.cs:2083-2106`). Conséquence pratique : la première
  fois, les dépendances manquantes s'affichent par `UniqueID` brut ; après un check, elles
  deviennent un **nom humain cliquable vers la page du mod**.

- **Écart** : le cache `UniqueId → nom humain + URL` et l'affichage cliquable des dépendances
  manquantes sont **manquants** côté StarHubFR. Se marie naturellement avec smapi.io.

### 3.5 Content packs

- `Manifest.ContentPackFor` → `mod.FrameworkID` + dépendance synthétique requise
  (`MainWindowViewModel.cs:449-454`).
- **Grouping visuel** `ModGrouping.ContentPack` : regroupe les content packs sous leur
  framework parent dans la grille (`MainWindowViewModel.cs:841-876`).
- **Écart** : StarHubFR détecte déjà parent/enfant. Le **regroupement visuel par framework**
  est un détail UI à évaluer.

### 3.6 Cachage des mods framework SMAPI

- `HideRequiredMods` (`MainWindowViewModel.cs:532-546`) cache et force-active trois mods
  internes : `SMAPI.ConsoleCommands`, `SMAPI.ErrorHandler`, `SMAPI.SaveBackup`. Ils
  n'apparaissent ni dans la grille ni dans le compte de mods activés.
- **Écart** : probablement **manquant** — ces mods encombrent probablement la liste
  StarHubFR. Nettoyage d'UX quasi gratuit.

### 3.7 Installation depuis une archive

- Deux chemins : `DirectModInstallAsync` (sans update handling) et `AddMods` (safe, avec
  détection d'update et gestion de l'ancienne version).
- **`DeleteOldVersion`** (`Manifest.cs:38`) et **`UpdateCautionMessage`** (`Manifest.cs:41`)
  sont des **champs custom** (extensions SMAPI tolérées) : le premier supprime
  automatiquement l'ancienne version ; le second affiche un message d'avertissement de
  l'auteur avant d'écraser la version existante (breaking change).
- **Écart** : `UpdateCautionMessage` est une **idée à porter** (champ absent = pas d'alerte,
  donc sans risque). Voir **B2-T7**.

### 3.8 Ce que Stardop ne fait pas (domaines d'avance StarHubFR)

Stardop ne fait **aucun** de ces choses, toutes livrées ou planifiées côté StarHubFR :

- **Diagnostic de log SMAPI** — Stardop ne lit `SMAPI-latest.txt` que pour en extraire les
  versions jeu/SMAPI/OS. Pas de carte de santé, pas de repliement du bruit, pas
  d'historique d'erreurs par version de mod.
- **Bissection guidée** — absente (livrée côté StarHubFR en A4).
- **Réparation de structure de dossier** — absente (`ModFolderRepairer` côté StarHubFR).
- **Validation de manifest au-delà de « UniqueID non vide »** — absente.
- **Détection de doublons ou de conflits** — absente (le dédoublonnage est silencieux).
- **Traduction FR comme différenciateur produit** — absente.

C'est le point de positionnement le plus net : **tout l'axe diagnostic de StarHubFR n'a pas
d'équivalent chez Stardop.**

---

## 4. Features manquantes ou à améliorer — classées

### 4.1 🔴 Haute valeur, nouvelles (pas dans la roadmap avant cet audit)

| Fonctionnalité | Origine Stardop | Renvoi roadmap | Effort |
|---|---|---|---|
| Compatibilité mods via **API live smapi.io** | `SMAPI.cs:93` | **A2** (repositionné) | M |
| **Configs par profil** (merge JSON non-destructif) | `MainWindowViewModel.cs:644`, `JsonTools.cs:26` | **B3-T5** | L |
| **Notes libres par mod** | `Profile.cs:6` | **B3-T6** | S |
| **`UpdateCautionMessage`** (alerte auteur au update) | `MainWindow.axaml.cs:2444` | **B2-T7** | S |
| Cache `UniqueId → nom humain + URL` + dépendances cliquables | `MainWindow.axaml.cs:2083` | *(à caser en A2 ou A1)* | S |

### 4.2 🟡 Déjà dans la roadmap — Stardop valide l'idée ou l'enrichit

| Roadmap | Sujet | Apport Stardop |
|---|---|---|
| **A2** | Compatibilité SMAPI | smapi.io > mods.jsonc (cf. §2) |
| **B2-T1** | ETA pendant le download | Enrichi : panneau downloads observable (vitesse/KBps, %, cancel, retry, anti-zombies) — `DownloadPanelViewModel.cs` |
| **B3-T1/T3** | Profil vide / duplication | Fait proprement (+ renommage, `IsProtected`, Apply/Cancel transactionnel) |
| **E1** | Packs distribuables | Format **modpack léger** : métadonnées + configs + notes, sans binaires ; import avec gestion des mods manquants (`MissingModsWindow`) |
| **A1-T1** | Activer toutes les dépendances | La cascade récursive existe déjà côté StarHubFR (flag opt-in) |

### 4.3 🟢 Détails d'UX

- **Panneau de téléchargements centralisé** avec badge compteur — `DownloadPanel`.
- **Quota Nexus quotidien visible** (`x-rl-daily-remaining`) → **B2-T6**. StarHubFR gère le
  rate-limit réactif (`Retry-After`) mais n'affiche pas le quota restant.
- **Multi-sélection Ctrl/Shift** sur lignes individuelles — StarHubFR a `toggleAllMods`
  (tout/pas tout) mais pas la sélection fine.
- **Restauration auto de la fenêtre** post-jeu (sonde le process SMAPI toutes 500 ms) +
  option `--start-smapi`.
- **Géométrie fenêtre persistée** — en SwiftUI, `NSWindow.setFrameAutosaveName` le donne
  quasi gratuitement.

---

## 5. À NE PAS porter (exclusions motivées)

| Piste | Décision | Raison |
|---|---|---|
| **`SimpleObscure`** (chiffrement clé Nexus) | **Écarté** | AES… mais clé + IV stockées **en clair à côté du ciphertext** dans `Notion.json` (`PairedKeys.cs`). Obfuscation, pas de la sécurité — **inférieure au Keychain macOS** que StarHubFR utilise déjà (`NexusUpdateChecker.swift`, account `nexusApiKey`). |
| **Activation par junctions/symlinks** | **Écarté** | Stardop lie les mods activés dans un dossier `Selected Mods` séparé + variable d'env `SMAPI_MODS_PATH`. Choix d'architecture **différent** du prefixe `X`/`.X` natif SMAPI de StarHubFR — plus complexe, dépendant des permissions OS. Notre convention est plus simple et plus fiable. |
| **Auto-update in-app façon Stardop** | **Écarté (pour l'instant)** | Move + restart, fragile sur macOS (`MainWindow.axaml.cs:1368-1477`). Si on l'ouvre un jour → **Sparkle**, pas ce bricolage. |
| **Parsing pseudo-JSON5 de Stardop** | **Écarté** | StarHubFR fait déjà du **vrai JSON5**. Supériorité locale. |
| **Dédoublonnage silencieux par UniqueID** | **Écarté** | Comportement trompeur (le doublon disparaît sans avertir). |

---

## 6. Positionnement StarHubFR vs Stardop

| Domaine | StarHubFR | Stardop |
|---|---|---|
| Diagnostic de log SMAPI | ✅ Carte de santé, repliement, historique | ❌ Extraction version uniquement |
| Bissection guidée | ✅ Livrée (A4) | ❌ |
| Réparation dossier / manifest | ✅ `ModFolderRepairer` + vrai JSON5 | ❌ |
| Traduction FR (différenciateur) | 🟡 En roadmap (C1–C5) | ❌ |
| **Compatibilité mods (smapi.io)** | 🟡 En roadmap A2, à repositionner | ✅ API live |
| **Configs par profil** | ❌ | ✅ Merge non-destructif |
| Intégration Nexus | 🟡 REST + `nxm://` + download | ✅ SSO, endorsement, virus scan GraphQL, panneau |
| Profils (export/import, duplication) | 🟡 En roadmap (B3, E1) | ✅ |
| Thèmes | 🟡 Limité | ✅ 12 thèmes |
| Stockage clé API Nexus | ✅ **Keychain** | ⚠ Obfuscation (`SimpleObscure`) |

**Lecture** : l'audit confirme le positionnement de la roadmap — StarHubFR gagne sur le
**diagnostic** et la **traduction FR**, Stardop gagne sur l'**écosystème Nexus** et la
**richesse de gestion des profils**. Le seul point qui modifie la roadmap est **A2** (smapi.io
plutôt que mods.jsonc).

---

## 7. Corrections — ce qui était supposé manquant mais existe déjà

Les analyses automatisées, menées à partir de la roadmap (parfois imprécise), ont déclaré
« manquant » plusieurs fonctionnalités **déjà présentes** dans le code StarHubFR. Vérifications :

| Fonctionnalité | Verdict initial | Réalité StarHubFR |
|---|---|---|
| Protocole `nxm://` | manquant | ✅ `StarHubTHApp.swift` + `handleNxmURL` + `NxmLink.swift` |
| Cascade de dépendances récursive | manquante | ✅ `StarHubTHViewModel.swift:472` (flag opt-in) + `:1711` |
| Filtre « mods avec config » | manquant | ✅ `ModListView.swift:58,145` (`configOnlyFilter`) |
| `Enable all` / `Disable all` | manquant | ✅ `StarHubTHViewModel.swift:4162` |
| Thumbnails Nexus | à vérifier | ✅ `picture_url` + `CachedAsyncImage` |
| Headers Nexus `Application-Name`/`Version` | à vérifier | ✅ `NexusRequestBuilder.swift:55-57` |
| Version du jeu Stardew Valley | manquante | ✅ Extraite du log (`SmapiHealthCard.swift:562`) |

---

## Annexe A — Pipeline téléchargement & mise à jour (analyse fine)

> Plongée end-to-end dans la détection de mise à jour, les trois chemins de
> téléchargement, le panneau de downloads observable et l'installation post-download.
> Matériau de référence pour les portages **A2** (smapi.io) et **B2-T1** (panneau downloads).
> Réf. `fichier:ligne` sous `Stardrop/`.

### A.1 — Détection de mise à jour : smapi.io

- **Endpoint** : `POST https://smapi.io/api/v3.0/mods` (`Utilities/External/SMAPI.cs:119`).
  **Pas de clé API** (public). Headers `Application-Name`/`Version`/`User-Agent` seulement.
- **Payload exact** (`ModSearchData`, `Models/SMAPI/Web/ModSearchData.cs`) :

  ```json
  { "mods": [{ "Id": "...", "InstalledVersion": "...", "UpdateKeys": ["..."] }],
    "apiVersion": "...", "gameVersion": "...", "platform": "...",
    "includeExtendedMetadata": true }
  ```
  `includeExtendedMetadata: true` est **obligatoire** pour récupérer le bloc `Metadata`
  (compatibilité) — sinon on n'a que `SuggestedUpdate`. Stardop soumet aussi les
  **dépendances absentes** (UniqueID seul, `SMAPI.cs:100-106`) pour résoudre leur nom + page.
- **Réponse** typée `List<ModEntry>` (`Models/SMAPI/Web/ModEntry.cs`) : par mod,
  `SuggestedUpdate { Version, Url }`, `Metadata { Name, Main, Unofficial, CustomUrl,
  CompatibilityStatus, CompatibilitySummary }`, `Errors[]`.
- **Arbre de décision** (`MainWindow.axaml.cs:2008-2074`) :
  - `SuggestedUpdate != null` → update dispo, URL = `SuggestedUpdate.Url`.
  - Sinon, si `Status == Unofficial && Unofficial != null && IsModOutdated(Unofficial.Version)`
    → URL unofficial.
  - Sinon `Metadata.Main` (info-only, pas un update).
- **Politique de rafraîchissement** : smapi.io est appelé **à chaque boot, sans TTL**
  (`MainWindow.axaml.cs:165`). `UpdateCache.LastRuntime` est sérialisé mais jamais
  consulté pour skipper un fetch. **À ne pas imiter** → poser un TTL (6-24 h) + bouton
  refresh manuel.
- **Pré-requis** : `GameDetails` (versions SMAPI/SDV/OS) parsé depuis `SMAPI-latest.txt`
  (regex `SMAPI (?<v>.+) with Stardew Valley (?<v>.+) on (?<v>.+)`, `Program.cs:38`),
  macOS : `~/.config/StardewValley/ErrorLogs/` (`Pathing.cs:66-68`). StarHubFR connaît déjà
  ces versions via le log (`SmapiHealthCard.swift:562`).
- **Cache** : `Cache/Versions.json` (`UpdateCache { LastRuntime, Mods: ModUpdateInfo[] }`)
  pour l'affichage boot hors-ligne (`GetCachedModUpdates`, `:1881`) ; `Cache/Keys.json`
  (`ModKeyInfo { UniqueId, Name, PageUrl }`) pour les noms de dépendances et `ModPageUri`.
- **SemVer** : `IsModOutdated` (`Mod.cs:207-215`) via `SemVersion.CompareSortOrderTo` (gère
  prereleases). Sentinelle `"bad-version"` (`Mod.cs:128`) pour filtrer les versions
  inparseables → `HasValidVersion()` gate aussi la soumission à smapi.io (`SMAPI.cs:96`).

### A.2 — Les 3 chemins de téléchargement

Pipeline commun : **sélection fichier → `GetFileDownloadLink` → `ValidateFileSafety` →
`DownloadFileAndGetPath` → `AddMods` → suppression archive → refresh caches**.

| Chemin | Entrée | Gate Premium | Sélection fichier |
|---|---|---|---|
| `nxm://` | `ProcessNXMLink` (`:1766`) | **non** (key/expiry du lien) | fileId direct du lien |
| Fiche mod | `InstallModViaNexus` (`:2285`) | **oui** (`download_link` sans key) | `GetFileByVersion(SuggestedVersion, flag)` |
| Bulk | `HandleBulkModInstall` (`:1640`) | **oui, dur** (abort sinon) | idem, **séquentiel** |

- **`GetFileByVersion`** (`NexusClient.cs:236`) : filtre les fichiers par version (SemVer),
  puis `flag` non null → match `Name`/`Description` contenant le flag ; sinon catégorie `MAIN`.
  **⚠ Feature `@variant` cassée** (voir A.5, bugs #5/#6).
- **`GetFileDownloadLink`** (`NexusClient.cs:324`) : non-Premium **toujours** forcé sur
  `Nexus CDN` quel que soit le réglage ; Premium → sélection par `short_name`. Pas de
  fallback si le serveur choisi est absent → null.
- **`ValidateFileSafety`** (`NexusClient.cs:628`) : single POST GraphQL
  `https://api.nexusmods.com/v2/graphql` :

  ```graphql
  query GetModFiles { modFiles(gameId: 1303, modId: X) { fileId, scannedV2 } }
  ```
  (`gameId: 1303` = Stardew Valley.) Retourne `true` si `scannedV2 != QUARANTINED`.
  **⚠ Bug** (A.5, #4) : `NOT_SCANNED`/`QUEUED` comptent comme safe.

**Portabilité StarHubFR** : 2 chemins sur 3 existent (`handleNxmURL`, `downloadModFromNexus`).
Manquent : **bulk install**, **sélection par version/flag** (`pickPrimaryFileId` prend juste
le main), **virus scan**. Détection Premium : `/validate` renvoie déjà `is_premium` →
l'exposer comme gate. Le flag `@` est déjà parsé côté StarHubFR, juste non exploité au
download — porter en **corrigeant** les bugs #5/#6.

### A.3 — Téléchargement + panneau observable

- **`DownloadFileAndGetPath`** (`NexusClient.cs:386`) :
  `HttpCompletionOption.ResponseHeadersRead` (streame dès les headers) + buffer 80 Ko +
  `CancellationTokenSource` fraîche par appel (annulable après `DownloadStarted`). Cleanup du
  fichier partiel en cas d'échec (`:423`). Result typé `NexusDownloadResult { Success,
  UserCanceled, Failed }`. Fire `DownloadProgressChanged` **à chaque chunk de 80 Ko** →
  throttling UI obligatoire.
- **4 events** (`Models/Data/ModDownloadEvents.cs`), tous identifiés par **URI** (clé de
  dédup) : `DownloadStarted { Uri, Name, Size?, CTS }`, `DownloadProgressChanged { Uri,
  TotalBytes }`, `DownloadCompleted { Uri }`, `DownloadFailed { Uri }`.
- **`DownloadPanelViewModel`** (`ViewModels/DownloadPanelViewModel.cs`) :
  - **Dédup** : même URI en cours (`NotStarted`/`InProgress`) → **ignoré** (« on ne casse
    pas un DL à 95 % ») ; état terminal (`Failed`/`Canceled`/`Successful`) → retiré puis
    ré-inséré (sémantique retry).
  - **Anti-zombies** au `Nexus.ClientChanged` (logout) : cancel tous les DL + clear la liste.
  - `InProgressDownloads` : compte `Failed + Canceled + InProgress` (« réclament une action
    user ») → drive le badge.
- **`ModDownloadViewModel`** (`ViewModels/ModDownloadViewModel.cs`) : dérivés via
  `ObservableAsPropertyHelper` + `.Sample(500ms)` (throttle 2 Hz) : `%`, libellé taille,
  `DownloadSpeedLabel`. **⚠ Bug** (A.5, #3) : vitesse = moyenne depuis `_startTime`, pas
  débit instantané.

**Portage SwiftUI** (= B2-T1, la grosse lacune UX côté StarHubFR) :
- `URLSessionDownloadTask` + `urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)`
  → progression live native (le système throttle déjà).
- `task.cancel(byProducingResumeData:)` → retry propre (**mieux** que Stardop).
- `DownloadStore: ObservableObject` avec `@Published var downloads: [DownloadItem]`, dédup
  par URL (in-flight → ignorer, terminal → remplacer).
- **Vitesse instantanée** par fenêtre glissante (delta bytes / delta temps) — ne pas porter
  la moyenne de Stardop.
- Cleanup : `urlSession(_:task:didCompleteWithError:)` — ne déplacer le tmp vers sa cible
  que sur `.completed`, sinon suppression.

### A.4 — Installation post-download (`AddMods`, `MainWindow.axaml.cs:2384`)

- **Multi-manifest** par archive (content packs) — pattern `pathToManifests` à copier.
- **`UpdateCautionMessage`** (`:2444`) : alerte auteur avant overwrite (= B2-T7). **Améliorer
  Stardop** : si l'utilisateur décline **un** manifest, Stardop skippe **toute l'archive** →
  skipper juste le manifest décliné.
- **`DeleteOldVersion` / `AlwaysAskToDelete`** (`:2475-2516`) : fenêtre 3-choix (Yes / Yes to
  all / No) via `FlexibleOptionWindow`. `TryDeleteMod` retry ×3 sans backoff.
- **Skip `__MACOSX/` + `.DS_Store`** (`:2549`) — crucial sur macOS.
- **Heuristique install-path** (`:2555-2565`) pour éviter `Mods/ModName/ModName/` — logique
  fragile, à porter **avec tests**.
- **Activation auto** (`EnableModsOnAdd`) + cascade `EnableRequirements` (`:2622`).
- **Queue d'install** : busy-wait `while(IsLocked) await Task.Delay(500)` (`:2390`) — à
  remplacer par un `actor` Swift ou une queue série (bug #10).

**Portage macOS** : `TryDeleteMod` ×3 est fragile — préférer `FileManager.trashItem(at:)`
(récupérable) ou `removeItem` avec `NSFileCoordinator` pour les fichiers tenus par SMAPI.

### A.5 — Bugs & à ne pas imiter (sélection sur le pipeline download/update)

| # | Bug | Leçon de portage |
|---|---|---|
| 1 | Auto-update corrompt l'URL sur **Apple Silicon** (`GitHub.cs:92-115`, concat au lieu d'assignation) | Si auto-update → Sparkle |
| 2 | `FileMode.CreateNew` (`NexusClient.cs:401`) → collision si 2 DL de même nom | Nom tmp unique ou `Create` |
| 3 | Vitesse = **moyenne** depuis le début (`ModDownloadViewModel.cs:82`) | Fenêtre glissante |
| 4 | Virus scan : `NOT_SCANNED`/`QUEUED` = safe (`NexusClient.cs:684`) | Distinguer « non vérifié » |
| 5/6 | Feature `@variant` **cassée** : `GetNexusFlag` retourne `@SwimItems` brut, pas de fallback MAIN, dernier match gagne (`Mod.cs:260`, `NexusClient.cs:262`) | Stripper `@`, fallback MAIN, premier match |
| 7 | `ParsedStatus` masque `Optional`/`Workaround`/`Abandoned`/`Obsolete` sans bump (`Mod.cs:73`) | Afficher tous les statuts non-Ok |
| 8 | Pas de contrôle client d'expiry NXM (`NexusClient.cs`) | `expiry < now` → message clair |
| 9 | `IsModOutdated` **jette** sur `SuggestedVersion` inparseable (`Mod.cs:207`) | `TryParse` |
| 10 | `AddMods` busy-wait `while(IsLocked)` sans timeout (`:2390`) | `actor` Swift |
| 11 | Pas de `Retry-After` côté Nexus (`NexusClient.cs:608`) | StarHubFR fait déjà mieux |
| 12 | Bulk install **séquentiel** (`:1667`) | Paralléliser, concurrence limitée |
| 13 | Endorsement désérialisé en string, fragile (`NexusClient.cs:507`) | Enum typé |
| 14 | `mods/{modId}.json` appelé 2× (details + thumbnail) | Mutualiser |
| 15 | **NXM désactivé sur macOS** côté Stardop (`MainWindow.axaml.cs:173`) | StarHubFR a déjà le bon pattern (Launch Services/`CFBundleURLTypes`) |

### A.6 — Points où StarHubFR est déjà devant

- **Retry-After réactif** sur 429 (Stardop ne lit que le quota — bug #11).
- **Détection d'archive par signature** des octets (`ModZipInstaller.detectedArchiveExtension`)
  — Stardop se fie au `file_name`.
- **Pattern macOS `nxm://` correct** — Stardop a NXM off sur macOS (bug #15), seul `--nxm`
  CLI marche. L'approche Launch Services de StarHubFR est la bonne.
- **Gestion fine localisée** du 403 (premium vs auth) et erreurs HTTP typées.

---

## 8. Limites de l'audit

- **Lecture statique** : aucune exécution de Stardop. Les comportements décrits sont lus dans
  le code, pas observés au runtime.
- **Recoupement asymétrique** : Stardop a été lu en profondeur par 4 analyses parallèles ;
  StarHubFR a été vérifié par `grep` ciblés sur les points litigieux, pas relu exhaustivement.
  Les verdicts « probablement manquant » côté StarHubFR restent à confirmer feature par
  feature au moment de l'implémentation.
- **Cible mouvante** : Stardop évolue ; cet audit est daté du 2026-07-31 (HEAD du dépôt à
  cette date).

---

## 9. Index des fichiers Stardop les plus pertinents

Tous sous `Stardrop/` :

- **Analyse de mods** : `Utilities/Internal/ManifestParser.cs`, `Models/Mod.cs`,
  `Models/SMAPI/Manifest.cs` (+ `ManifestDependency`, `ManifestContentPackFor`),
  `Models/SMAPI/Web/ModEntry.cs` (+ `ModEntryMetadata`, `ModEntryVersion`, `ModSearchData`),
  `Utilities/External/SMAPI.cs`, `Models/Data/{ModKeyInfo,ModUpdateInfo,UpdateCache}.cs`.
- **Nexus** : `Utilities/External/NexusClient.cs`, `Utilities/NexusWebsocket.cs`,
  `Utilities/NXMProtocol.cs`, `Models/Nexus/GraphQL/*`, `Models/Nexus/Web/*`.
- **Profils** : `Models/Profile.cs`, `Models/ProfileExternal.cs`,
  `ViewModels/ProfileEditorViewModel.cs`, `Views/ProfileExportWindow.axaml(.cs)`,
  `Views/MissingModsWindow.axaml(.cs)`.
- **Transverse** : `ViewModels/MainWindowViewModel.cs`, `Views/MainWindow.axaml.cs`,
  `Utilities/External/{GitHub,SMAPI}.cs`, `Models/{Settings,Theme,Config}.cs`,
  `Utilities/{SimpleObscure,JsonTools,Pathing,Helper}.cs`.
