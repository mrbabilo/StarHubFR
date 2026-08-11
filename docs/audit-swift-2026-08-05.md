# Audit Swift — 2026-08-05

Audit large du code Swift de StarHubFR, succédant à celui du 2026-08-04 (52 bugs,
8 hauts corrigés). Objectif de cette passe : couvrir au-delà des patterns transverses
déjà traités (CRLF, copies divergentes, concurrence `@Published`, format par nom) et
**persister la liste détaillée des findings** — le défaut de l'audit précédent était
que ses 20 moyens + 24 bas n'avaient été consignés nulle part.

## Méthode

- **8 zones** couvrant les 91 fichiers, auditées par subagents en **vagues de 2-3**
  (un fan-out de 7 avait causé stalls/429 le 2026-08-04 — mémoire
  `parallel-audit-orchestration`).
- Chaque finding **re-vérifié par lecture directe** du code avant consolidation (les
  agents se trompent ; mémoire `critique-upstream-before-integrating`).
- Contexte des corrections déjà appliquées fourni à chaque agent pour éviter le
  double-emploi.
- Types de bugs cherchés : correctness, data-loss, crashes, concurrence, fuites de
  ressources, sécurité (path traversal, validation d'entrée), UX (silence sur erreur,
  état incohérent), edge cases (vide, unicode, CRLF, chemins).

## Périmètre

- **91 fichiers Swift, ~28 300 lignes** sous `StarHubTH/`.
- Concentration de fragilité : `StarHubTHViewModel.swift` (4080 lignes, non testé),
  `ModListView.swift` (1687), `MainView.swift` (1126), `ModZipInstaller.swift` (1037).
- Core testable (Package.swift, 559 tests) : Models/, SaveManager, ModItem, managers
  de backup, parsing. Le reste (ViewModel, Views) n'est validé que par build.

## Corrections déjà appliquées (contexte — ne pas re-auditer à l'aveugle)

### Audit 2026-08-04 — 8 bugs haute sévérité (tous corrigés)

| # | Site | Bug |
|---|------|-----|
| 1 | `ModZipInstaller.snapshotUserConfigs` | traductions i18n perdues à l'update/backup |
| 2 | `SaveManager.branchFromBackup` | `split(".")[0]` amputait les saves à points |
| 3 | `DescriptionBlockParser` / `LogNoise` | CRLF cassait le Markdown (×5 sites) |
| 4 | `BisectionRunner.recordLogEvidence` | evidence décalée d'une étape |
| 5 | `StarHubTHViewModel.loadProfiles` | mutation `@Published` depuis background |
| 6 | `ModZipInstaller` | garde anti-zip-bomb désactivée pour RAR/7z |
| 7 | `ModZipInstaller` | format d'archive décidé par extension (drag-drop) |
| 8 | `ModListView` / `ModDetailView` | double-clic toggle → mauvais sens |

### Groupes A–G (2026-08-04 soir → 2026-08-05) — 12 moyens + ~14 patterns transverses

**Moyens (M1–M13)** : `cloneSaveFolder` propagation d'erreur XML ; `.stale_*` via
`removeItemGrantingWriteAccess` ; `ManifestVersionPatcher` JSON5 ; `collectUniqueIds`
relativePath canonique ; `strippingCPPrefix` unique ; `resolveModFolder` exact match ;
`extractArchive` par signature ; statut HTTP du download CDN ; `QuarantineMessage`
porteur typé ; bouton « info » mort retiré ; « Visit website » en vrai `Link` ;
`SaveTimelineView` label « Annuler ».

**Tour 2026-08-05 (D→G)** : `CachedAsyncImage` reset d'état ; éditeur de config
case `.string` (parse + UI + réécriture achevés) ; `ViewModel:1223` chemin relatif
canonique (jumeau M6 + symlink) ; source unique `OSJunk` (4ᵉ copie + divergence
warning `Icon\r`/`.Spotlight-V100`) ; `SaveManager`/`ModInstallBackupManager`/
`toggleMod` rollbacks loggés ; `performDelete` alerte ; `scanMods` guard sur main ;
`selectCustomAvatar` vérifie la copie ; `SmapiInstaller` marqueur en `do/catch`.

**`try?` laissés délibérément (best-effort légitime)** : `ModZipInstaller:923` (touch
mtime, quasi impossible à échouer après `copyItem` réussi), `BisectionSnapshot:60`
(confort de reprise après crash).

## Findings restants

> _À remplir après consolidation des 3 vagues d'audit et re-vérification._

### Haute sévérité

> ✅ **Les 9 hauts ont été corrigés le 2026-08-05** (commits `cc737f1` print→log,
> `d82cc3b` échappement XML + validateJson, `df1aeda` rollback install,
> `6bdb0b8` bisection recovery, `582bf06` zip-slip, `dd6b4d1` ForEach + saveIndex).
> Le tableau est l'instantané de l'audit ; les détails de chaque correction sont
> dans les messages de commit.

| Site | Bug | Scénario d'échec |
|------|-----|------------------|
| `SaveManager:540` (`replaceFirstTag`) | **Injection XML** : valeurs saisies (nom/ferme/conjoint/favThing) interpolées brutes dans `<tag>\(value)</tag>` sans échapper `<`/`&`. | Ferme « D&D Farm » → `<farmName>D&D Farm</farmName>` (`&` nu invalide) → parse nul au `fetchSaves` suivant → save live corrompue, disparaît de la liste. |
| `SaveManager:578` (`modifyInternalSaveNames`) | Même injection XML sur la branche clone. | Cloner « Bob & Alice » → clone illisible par Stardew dès la 1re ouverture, silencieusement. |
| `ModZipInstaller:911` | `removeItem(destPath)` **puis** `copyItem` sans backup ni rollback (cas rename/keepExisting/useNew/nouveau). | `copyItem` échoue (disque plein) → l'ancien dossier est déjà détruit, sans recours. Collision avec un mod en pause `.X` possible. |
| `BisectionRunner:270` (`restoreAndStop`) | En mode recovery post-crash, `allEnabled` est vide ; `apply(restore)` filtre par `allEnabled` → `applyEnabledFolders([])`. La garde `!restore.isEmpty` ne couvre pas ce cas. | Bouton « Restaurer » post-crash **désactive toute la modlist active** au lieu de restaurer — data-loss au pire moment. |
| `StarHubTHViewModel:1796` & `3944` | Rollbacks `toggleMod`/`toggleAllMods` en `print(...)` au lieu de `log(.error)` (**régression introduite Groupes F/G** ce tour). | Mod bloqué dans `.stale_UUID` invisible — le message n'apparaît **pas** dans l'onglet Journaux (audible seulement en console). |
| `SaveTimelineView:76` | `ForEach(backups.indices, id: \.self)` alors que `listBackups` trie par timestamp **décroissant** → @State (`noteTag`/`noteText`) hérité par la rangée qui prend l'index. | Nouveau backup décale les index → note éditée persistée sur le **mauvais** backup au clic Save. |
| `ModConfigEditorView:233` (`validateJson`) | Un texte **vide** est déclaré valide (`isInvalidJson = false`) → bouton Save reste actif. | Champ vidé → clic Save → `config.json` écrasé par un fichier vide → SMAPI ne peut plus parser la config du mod. |
| `ModZipInstaller:509` (`extractArchive`) | **Zip-slip** : aucun filtrage des entrées `../` ; `guardAgainstSymlinks` ne couvre que les symlinks. | Archive malicieuse `.7z`/`.rar` avec entrée `../../../…` → écrit hors `tempDir` (la mémoire « DroppedContentRecognizer anti path-traversal » concerne le *scanner*, pas l'extraction). |
| `ModInstallBackupManager:76` (`saveIndex`) | `try?` sur l'écriture de `install_metadata.json` → backup copié sur disque mais non référencé dans l'index (orphelin). | Disque plein / perm → backup invisible dans la liste, impossible à restaurer ou supprimer depuis l'UI. |

### Moyenne sévérité

> ⚠️ **18 sur 23 corrigés** — 2026-08-06 (`353333e`→`99138ac` : crash
> `linkTarget`/`split`, `InstallPreview`, watcher Journaux, `ForEach` fiches,
> confirm. `cleanDisabledMods`, règle benign, jumeau M4, RMW
> `installedModRegistry`, `steamUsername`, `setNexusApiKey`, `deleteBackup`
> read-only, snapshot bissection), puis `f0bb19e`, 2026-08-10 `d0a906d` et 2026-08-11 le throttle de
> `ModInstallView`.
> `VM:1811` était déjà corrigé (régression print→log `cc737f1`).
>
> Le décompte « 13 sur 23 » écrit ici le 2026-08-06 (`9666217`) était périmé dans
> l'heure : `f0bb19e` du même jour a fermé les deux UX (confirmation de
> suppression de backup, `pendingToggle` annulé au `.onDisappear` — dans les
> **deux** vues), et `d0a906d` a fermé le rate-limit Nexus fragmenté du groupe 4
> (`NexusRateLimitGate`, back-off partagé consulté par chaque chemin réseau).
> Table re-vérifiée ligne à ligne le 2026-08-11.
>
> **Les 5 restants** (numéros de ligne re-relevés le 2026-08-11 — ils avaient dérivé) :
>
> - `StarHubTHViewModel:3284/3344/3375/3386` — `deleteSave`, `duplicateSave`,
>   `branchFromBackup`, `restoreBackup` appellent `SaveManager` **sur le main
>   thread**. Demande un refactor d'API void/Bool → async.
> - `SaveManager:376/826` — `updateSave`/`updateInventory` toujours sans verrou
>   fichier (`NSFileCoordinator`).
> - `SaveManager:401` — remariage. `cleanDivorceNPCFriendship` démote bien
>   l'ancien conjoint (`Married`→`Friendly`, `WeddingDate` retiré, l. 485-490),
>   mais **rien ne promeut le nouveau**. Bloqué : `~/.config/StardewValley/Saves`
>   est vide, pas de save de test — et le XML de mariage est à mesurer, pas à
>   deviner.
> - `NexusUpdateChecker:424-428` — classification `lastError`. Le cas
>   `successCount>0` est intentionnel ; seul `==0` reste trompeur.
> - `SaveCopySheets:38/103` — `dismiss()` inconditionnel. ⛔️ Le scénario écrit
>   plus bas (« silence total ») est **inexact** : le ViewModel affiche bien un
>   modal d'échec (`duplicateSaveError`/`branchError`). Il ne reste que la feuille
>   qui se ferme sur un échec, ce qui vaut « bas », pas « moyen ».

Dans la table : ✅ = corrigé, ⛔️ = ouvert. Les numéros de ligne sont ceux de
l'audit du 2026-08-05 sauf mention « auj. ».

| Site | Bug | Scénario |
|------|-----|----------|
| ✅ `ThaiTranslationTable:109` | **Crash** `linkTarget` : si `)` précède `(`, `index(after: open)..<close` a lowerBound > upperBound. | Cellule Nexus d'un dépôt tiers contenant `)text(` → crash fatal (`Range requires lowerBound <= upperBound`). Source externe non contrôlée. |
| ✅ `ManifestVersionPatcher:79` | **Jumeau de M4** : `replaceVersionValue` regex sur le `raw` **non nettoyé** alors que `extractVersionValue` strip les commentaires. Le commentaire « extract and replace always agree » (l.83) est faux. | decide() lit la vraie version, le patch écrit dans un `"Version"` commenté → patch inefficace, update re-flaggué. |
| ✅ `StarHubTHViewModel:2880/2913` | RMW sur `installedModRegistry` : `load → mutate → save` sans lock couvrant la séquence (le lock ne protège que chaque appel). | 2 scans concurrents s'écrasent → `nexusVersion` perdu → faux « update available » perpétuel. |
| ✅ `StarHubTHViewModel:832` | `steamUsername.isEmpty` checké avant la publication `main.async` de `fetchSteamUser` (922). | Le fallback « Farmer » est toujours planifié et écrase le vrai nom (main FIFO) → nom par défaut faux au 1er launch. |
| ✅ `StarHubTHViewModel:2223` | `setNexusApiKey` met `hasNexusApiKey = true` sans vérifier le retour de `SecItemAdd`. | UI dit « clé configurée » si la Keychain refuse → le prochain `checkNexusUpdates` part en `.noApiKey`. |
| ✅ `StarHubTHViewModel:1811` | `performToggle` catch en `print` au lieu de `log(.error)` (`toggleAllMods` logge correctement à 3982). | Échec de toggle invisible dans l'UI et les Journaux. |
| ✅ `NexusUpdateChecker:723/758` | 429 silencieux : `fetchRawDescription`/`fetchChangelogs` retournent `""` sur tout non-200, ignorant le circuit rate-limit de `check()`. | Navigation entre mods pendant un 429 → nouvelles requêtes sans back-off → aggravation du ban. |
| ⛔️ `NexusUpdateChecker:425` | Classification `lastError` : une requête post-abort peut l'écraser. Le cas `successCount>0` est **intentionnel** (commentaire), mais `==0` reste trompeur. | Un 404 en vol après un 429 masque le message « rate-limited ». |
| ✅ `ModInstallView:672` | `fetchNexusMetadata` boucle sans throttle (commentaire « bounded concurrency » trompeur). | Pack de 20 mods → rafale de ~40 requêtes → 429/ban. |
| ✅ `ModInstallBackupManager:299` | `deleteBackup` en `removeItem` simple au lieu de `removeItemGrantingWriteAccess`. | Backups read-only (POSIX hérités) non supprimables, erreur sans workaround UI. |
| ✅ `SmapiLogDiagnostics:451` | Règle benign `.apiIntegration` matche « couldn't get the »/« failed to get the » sans exiger « API ». | Erreur réelle classée benign → carte « sain » trompeuse, mod absent du top 5. |
| ✅ `BisectionSnapshot:58` | `save` en `try?` : l'unique filet de récupération après crash avale l'erreur disque. | Disque plein → reprise impossible, modlist laissée à moitié en pause, sans avertissement. |
| ⛔️ `SaveManager:396` (auj. `401`) | Divorce/remariage : la démotion de l'ancien conjoint est faite (`Married`→`Friendly`, `WeddingDate` retiré, l. 485-490) ; c'est la **promotion du nouveau** qui manque. | Changement « Abigail → Penny » → glitch du nouveau conjoint à l'arrivée en ferme. |
| ⛔️ `SaveManager:371/814` | Pas de verrou fichier : `updateSave`/`updateInventory` (ou autosave du jeu) peuvent s'entrelacer. | Deux écritures concurrentes → dernier gagne, changements de l'autre perdus. |
| ⛔️ `StarHubTHViewModel:3117/3148/3159/3057` | `duplicateSave`/`branchFromBackup`/`restoreBackup`/`deleteSave` ne dispatchent pas hors main (contrairement à `editSave`/`saveInventory`). | Copie de plusieurs centaines de Mo → spinner bloqué, rainbow. |
| ✅ `SaveTimelineView:88` | `onDelete` sans confirmation, alors que la restauration (réversible, juste à côté) en a une. | Clic « trash » → backup supprimé sans avertissement (asymétrie du risque). |
| ✅ `LogsView:371` | Le watcher SMAPI n'est relancé au `onAppear` que si les entrées sont vides. | Quitter/revenir à l'onglet Journaux → suivi live de `SMAPI.log` perdu. |
| ✅ `SettingsView:238` | `cleanDisabledMods` supprime en lot tous les mods en pause sans confirmation. | Un clic efface tous les mods désactivés du profil (juste un message post-op). |
| ✅ `DescriptionBlocksView:190/200` | `ForEach(id: \.offset)` → @State `isExpanded` des spoilers fuit entre fiches. | Spoilers dépliés sur la fiche du mod A se retrouvent dépliés sur la fiche B. |
| ✅ `SaveCopySheets:61` | `split(separator: ".")[0]` sans garde. | `lastPathComponent` vide → crash à l'ouverture de la feuille de branchement. |
| ⛔️ `SaveCopySheets:37/98` (auj. `38/103`) | `duplicateSave`/`branchFromBackup` suivis de `dismiss()` inconditionnel. | Échec (disque plein, nom pris) → feuille fermée, aucune sauvegarde créée. ⛔️ Le « silence total » écrit ici est faux : le ViewModel affiche un modal d'échec. |
| ✅ `ModListView:1456` / `ModDetailView:206` | `pendingToggle` (debounce) jamais cancellé au `.onDisappear`. | `toggleMod` se déclenche pour un mod désaffiché (scroll rapide, navigation). |
| ✅ `InstallPreview:95` | `.frame(maxHeight: visibleFrame.height)` entier, pas 60 % comme l'indique le commentaire. | Boutons d'action poussés hors vue sur un pack de 50 mods. |

### Basse sévérité

Regroupés par thème (~40 findings). Sévérité basse = scénario rare, cosmétique, ou sans impact
fonctionnel réel. Les sites précis sont conservés pour action ciblée.

> ✅ **Les deux findings « Sécurité » ont été corrigés le 2026-08-10** :
> l'allowlist de scheme des descriptions Nexus (`a4d7d9e` — http/https + `nxm`,
> appliquée aux 4 points de construction de lien/image) et la validation du
> `modId` avant interpolation dans l'URL de l'API (`0758206` —
> `NexusRequestBuilder.isValidModId`, entier strictement positif). Ils étaient
> restés listés comme ouverts ici jusqu'au 2026-08-11.
>
> ✅ **Lot parsing/encodage + localisation traité le 2026-08-11** (`a3b2e8e`, `55e5a5e`).
> Corrigés : BOM UTF-32 (les deux boutismes), échappement des clés de
> `I18nOutline`, `fold` sans les sauts de ligne, `replaceFirstTag` sur balise
> vide, profondeur bornée, les 9 chaînes en dur de `ModConfigEditorView` /
> `AppChangelogView`, le compteur de `ModInstallBackupsView`, et un canal
> d'avertissement pour `SmapiInstaller`. Chaque écart .NET a été mesuré sous
> mono, pas déduit.
>
> ⛔️ **Deux findings de cette liste sont faux** :
> - `extractTag:284` (décodage des entités) était **déjà corrigé** (`d82cc3b`),
>   et le « regex CRLF » n'en est pas un : `[^<]` accepte déjà les sauts de ligne.
> - `TranslationTokens:96` (« `mailCommand` sans limite de mot ») : appliquer la
>   limite **casserait** le parc. Mesuré sur les mods installés, `%revealtaste`
>   colle son argument (`%revealtasteSenS767`) dans 237 valeurs. Le vrai défaut
>   est ailleurs : aucune de ces 237 valeurs ne porte le `%%` de fermeture
>   qu'exige notre reconnaissance, donc le jeton n'est **jamais** protégé.
>   Corriger demande de connaître la fin exacte du jeton côté jeu — à ne pas
>   deviner.
>
> ⏳ Non traité dans ce lot : `MainView:501` (a11y). La clé existe pourtant dans
> les deux JSON ; seul `NSLocalizedString` y contourne `vm.L` et ne suit donc pas
> un changement de langue en session. Le composant `SidebarBadgeItem` n'a pas
> accès au ViewModel, et lui ajouter un champ fait dépasser le vérificateur de
> types sur le `body` de `MainView` (constaté). Demande soit un
> `environmentObject` (absent du projet), soit un découpage de `MainView`.

- **Erreurs silencieuses / `print` au lieu de `log`** : `ModZipInstaller:951` (catch snapshotUserConfigs), `performToggle:1772` (skip), `selectCustomAvatar:3108`, `SmapiInstaller:299` (xattr quarantine).
- **Gels UI (main thread)** : `evaluateThaiTranslationStatus:3315` (~180k `fileExists` mods×thai), `deleteMod:4043` (`removeItem` synchrone sur gros mod), `HomeView:274` (`refresh()` à chaque `onAppear`).
- **Parsing / encoding edge cases** : `I18nFileDecoder:54` (UTF-32 LE confondu UTF-16 LE → caractères nuls), `I18nOutline:160` (échappement `\"` conservé vs JSON déséchappé → clé orpheline), `TranslationTokens:96` (`mailCommand` sans limite de mot), `I18nOutline:127` (`depth` négatif sur JSON malformé), `I18nLocaleResolver:176` (`fold` whitespace au lieu de `whitespacesAndNewlines`), `extractTag:284` (pas de décodage entités → double-encodage), `replaceFirstTag:526` (regex `[^<]+` exige ≥1 char), regex CRLF dans `extractTag`.
- **Localisation (chaînes hardcoded contournant `vm.L`/L10n)** : `ModConfigEditorView:223/385/404/406`, `AppChangelogView:38/41`, `MainView:501` (`NSLocalizedString` brut pour l'a11y — clé probablement absente des JSON), `ModInstallBackupsView:27` (`lowercased()` sur chaîne localisée).
- **Sécurité (schéma URL / injection)** : ✅ `DescriptionBlockParser:343/671` (pas d'allowlist `http(s)` → `javascript:`/`file:`) — corrigé `a4d7d9e` ; ✅ `NexusUpdateChecker:599` (`modId` interpolé sans validation numérique) — corrigé `0758206` ; reste `LogNoise:62` (`modNamePrefix` prend « http » comme nom de mod).
- **Concurrence / lifecycle** : `applyEnabledFolders:3589` (pas de guard `isApplyingProfile`), `BisectionRunner:94` (`start` sans garde `interruptedSnapshot`), `installSmapi:1863/1873` (capture `self` forte), `categoryCache:2362` (dict mutable sans lock), `loadSmapiLog:189` (timing : log de la mauvaise étape), `SmapiInstaller:72` (`@Published` muté sans main explicite).
- **Attribution / faux négatifs** : `SmapiLogDiagnostics:328` (`modName` inclut la version → `resolveModFolder` ne matche pas), `LogNoise:121` (`warningGroupRange` header orphelin).
- **UX / logique UI** : tri saves non localisé, `ModListView:575` (état vide affiche le label *opposé*), `DescriptionBlockParser:658` (perf O(n²) `firstIndex`), `DependencyTreeView:88` (`onTapGesture` sur rangée à boutons), `BisectionCard:155` (Yes/No sans debounce double-clic), `InstallPreview:95` (déjà en moyen).
- **Data secondaire** : `SaveManager:567` (clone `_old` orphelin), `SaveManager:837` (suppression inventaire no-op sur `isObject==true`), `SaveManager:860` (`updateInventory` reformatage XML complet), `TranslationBackupFinder:68` (`fileExists` vrai pour un dossier `fr.json`), `ModDetailCache:16` (cache sans TTL/invalidation), `ModFolderRepairer:453` (collision timestamp `nowStamp` à la seconde), `ModConfigEditorView:261` (ordre des clés perdu après save), `SavesView:117` (branche morte `th`), `NxmLink:14` (`userId` parsé mais jamais lu).

## Patterns transverses

Synthèse consolidée des 8 zones. Plusieurs recoupent des mémoires existantes
(`crlf-is-one-character`, `diverging-copies-hide-bugs`, `trust-bytes-not-filenames`,
`swift-concurrency-and-identity-traps`) — ils persistent.

1. **Injection / échappement XML absent** (`SaveManager`) — le chantier majeur de cette
   passe. Aucune helper `xmlEscape`/`xmlUnescape` : les valeurs saisies sont interpolées
   brutes dans le XML des saves (`<tag>\(value)</tag>`). Couvre les 2 HAUT (540, 578) et le
   double-encodage à la lecture (extractTag:284). Une paire helper + application aux 3 sites
   ferme la famille. Même famille que « trust bytes / CRLF ».

2. **`print` au lieu de `log(.error)` sur chemins d'erreur utilisateur** — 5 sites (rollbacks
   `toggleMod` 1796/3944, `performToggle` 1811, `selectCustomAvatar` 3108, skip 1772). Les
   messages critiques (mod bloqué dans `.stale_UUID`) n'arrivent **pas** dans l'onglet
   Journaux. ⚠️ **Inclut une régression introduite ce tour** : les rollbacks loggés en
   Groupes F/G utilisent `print` au lieu de `log(level: .error)`.

3. **`ForEach(id: \.self / \.offset)` sur indices** → @State qui fuit entre rangées quand
   l'ordre change (`SaveTimelineView:76` HAUT, `DescriptionBlocksView:190`). Bannir le
   pattern ; exiger `Identifiable`.

4. **Confirmations absentes pour actions destructives** — asymétrie systémique : la
   suppression (irréversible) de backups / saves / mods désactivés ne confirme pas, alors
   que la restauration (réversible) le fait. 5 sites (SaveTimelineView, SavesView ×3,
   SettingsView).

5. **Parsers manifest / commentaires divergents** (3+ copies) — `ManifestJSON.sanitize`
   (string-aware), `ManifestVersionPatcher.extractVersionValue` vs `replaceVersionValue`
   (jumeau M4), `ModFolderRepairer`. Famille `diverging-copies-hide-bugs` : unifier sur le
   parseur string-aware.

6. **Rate-limiting Nexus fragmenté** — `check()` borne (sémaphore 6 + abort + Retry-After),
   mais `fetchRawDescription`/`fetchChangelogs`/`fetchSingleMod` l'ignorent → aggravation du
   ban au niveau du compte. Un `NexusRateLimiter` central manque.

7. **Sécurité : zip-slip + schémas URL non filtrés** — `extractArchive` (entrées `../`) et
   `DescriptionBlockParser.convertLinks` (`javascript:`/`file:`). Aucune allowlist. Sources
   externes non fiables (archives Nexus, descriptions d'auteurs).

8. **Travail filesystem / boucle sur main thread** — `deleteMod`, `evaluateThaiTranslationStatus`,
   et 4 write-paths save non dispatchés. La moitié des write-paths est hors main, l'autre non
   (incohérent, commentaires contradictoires).

9. **`try?` sur persistance critique** — `saveIndex` (orphelins backup), `BisectionSnapshot.save`
   (filet de récupération), `snapshotUserConfigs`. Distinction à faire : un *cache* peut avaler
   (`ModErrorHistory`, `ModDetailCache`), un *filet de récupération* doit signaler.

10. **Chaînes anglaises hardcoded** — contournent `vm.L`/`assets/{en,fr}.json`
    (`ModConfigEditorView`, `AppChangelogView`, `MainView` a11y). Brisent le bilingue.

## Priorisation suggérée

> 📌 **Cette section est l'instantané du 2026-08-05.** Au 2026-08-11 tout ce qu'elle
> désigne comme urgent est corrigé, y compris le rate-limiter Nexus unifié
> (`d0a906d`). Ce qui reste à arbitrer se lit dans la liste « les 6 restants » de
> la section Moyenne sévérité et dans les thèmes basse sévérité non cochés.

- **À corriger en premier (data-loss / crash / sécurité)** : l'injection XML SaveManager
  (#1, 2 HAUT) — helper `xmlEscape`/`xmlUnescape` ; `BisectionRunner.restoreAndStop` (désactive
  la modlist en recovery) ; `ModZipInstaller:911` (rollback manquant) ; `validateJson` vide
  (config.json écrasé) ; `extractArchive` zip-slip (allowlist `destDir`).
- **Régression de ce tour à reprendre** : convertir les `print` des Groupes F/G en
  `log(level: .error)` (rollbacks toggleMod/restoreBackup, marqueur SMAPI, avatar) pour qu'ils
  soient visibles dans l'onglet Journaux.
- **Ensuite (moyens à impact large)** : rate-limiter Nexus unifié ; `ForEach` Identifiable ;
  échappement manifest unifié ; dispatch des write-paths save hors main.

## Compteur

- ~9 haute sévérité, ~23 moyenne, ~40 basse — **~72 findings** au total (l'audit 2026-08-04 en
  avait recensé 52, dont 8 hauts et 12 moyens déjà corrigés ; cette passe a élargi le périmètre
  au-delà des patterns transverses et a consolidé les moyens/bas qui n'étaient consignés nulle
  part).

**État au 2026-08-11** (re-vérifié dans le code, pas déduit des messages de commit) :

| Sévérité | Corrigés | Restants |
|----------|----------|----------|
| Haute (9) | 9 | 0 |
| Moyenne (23) | 18 | **5** — write-paths save, verrou fichier, remariage NPC, `lastError`, `dismiss()` des feuilles |
| Basse (~40) | lot parsing/encodage/localisation (`a3b2e8e`, `55e5a5e`) + les 2 de sécurité (`a4d7d9e`, `0758206`) | le reste des thèmes, dont 3 bloqués (voir ci-dessous) |

⚠️ **Périmètre de cette re-vérification** : la table des moyens a été relue ligne
à ligne dans le code, et deux thèmes basse sévérité (parsing/encodage,
localisation, sécurité). Les **six autres thèmes basse sévérité** — `print` au
lieu de `log`, gels UI, concurrence/lifecycle, attribution, UX, data secondaire —
**n'ont pas été re-vérifiés** : ils peuvent contenir des lignes déjà corrigées,
comme la sécurité en contenait deux.

**Bloqués sur un fait externe, pas sur du temps** : le remariage NPC (pas de save
de test, `~/.config/StardewValley/Saves` est vide), le jeton `%revealtaste` (il
faut la syntaxe de fin exacte côté jeu — 237 valeurs réelles en dépendent), et
`MainView:501` (le corriger sature le vérificateur de types sur le `body` de
`MainView` ; demande un `environmentObject` ou un découpage).

> ⚠️ **Ce document se périme vite.** Il a listé comme ouverts pendant 5 jours
> trois findings corrigés le 2026-08-10, et son décompte des moyens était faux
> dans l'heure qui a suivi son écriture. Avant d'attaquer une ligne, passer
> `git log -S` sur le symbole concerné — mémoire `verify-open-tasks-are-still-bugs`.
