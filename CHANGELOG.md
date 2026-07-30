# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The SMAPI diagnostics owe a lot to [SMAPILogDoctor.py](https://github.com/ZeroXPatch/Projects-for-Nexus-Mod/blob/main/SMAPILogDoctor.py)
by ZeroXPatch (the idea of a player-facing SMAPI log doctor), to SMAPI's own
[log parser](https://smapi.io/log/), and to the [SMAPI sources](https://github.com/pathoschild/SMAPI)
where the exact log format was verified.

## [Unreleased]

### Added
- **Repetitive log lines are folded into families** — a real SMAPI log is ~90 % TRACE, dominated by a few shapes with a varying name (`Content Patcher loaded asset 'X'` ×646, `Loaded 'X'` ×396). Runs of five or more consecutive same-shape lines now collapse into one expandable row showing the first message and "N similar lines", taking a 4000-line log down to a few hundred readable rows. Nothing is discarded: the detail is one click away, and "copy all" and the entry count still cover every real line.
- **Optional per-mod grouping in the Logs tab** — a toolbar toggle switches the log from one chronological stream to collapsible per-mod sections, each with its line count and a red or orange dot so a mod with errors can be spotted while collapsed. Sections are ordered by what needs attention (errors, then warnings, then the noisiest), and SMAPI's own output gets its own section that always sorts last. Chronological remains the default.
- **Per-version error tracking for each mod** — StarHubFR now records the errors and warnings a mod logs, per mod version, and the mod detail page shows them under **"Error tracking"**: counts, when they were last seen, a few sample messages, and a marker on the version you currently have installed. This answers the question a new version raises — does it behave worse than the one before? Stored as its own file so the install registry stays untouched, and forgotten when a mod is deleted.
- **Jump between a diagnostic and what it refers to** — every mod named in the health card carries two buttons: one opens it in the Mods list (scoped to it), the other filters the log down to its lines. Risk-category headers also get a button showing SMAPI's own block for that category — the complete list of affected mods as written in the log, beyond the few the card displays.
- **Plain-language SMAPI diagnostics** — the health card now explains what the log means instead of quoting it. It leads with **"What you can do"**: actionable advice in the user's language (install a missing dependency, remove a duplicate install, update a mod that doesn't support your game version, back up saves before playing with a save-serializer mod, narrow down a crash by halving the list of code-patching mods). Below it, each risk category — mods changing game code, mods changing your saves, broken mods, console-access mods — is listed with a one-line, jargon-free explanation of what it means for the player, plus the mods logging the most errors. Risk categories are parsed from SMAPI's own warning-group sections (skipping the separator line, unlike the reference implementation) and are treated as informational, so a large modlist doesn't read as permanently "unhealthy".
- **"Errors you can ignore" in the SMAPI diagnostics** — known-harmless log lines are recognized and explained rather than alarming the player: platform sign-in (GOG Galaxy), an optional integration with another mod that couldn't be wired up (typically a config menu, usually a version gap), an optional companion mod that isn't installed, and mods failing to read their own data. Each entry names the mod, shows how many times it recurred, quotes the original message as evidence, and offers a button that scopes the Logs view to that mod's lines. Matching works on families of phrasings rather than exact wordings, and a mod that declares its own warning ignorable is taken at its word. Crucially these no longer feed the per-mod error tally, which was blaming working mods for optional integrations they can live without; genuine errors keep their full weight.
- **SMAPI health card in the Logs tab** — a new collapsible card above the log list (visible on the All and SMAPI tabs) summarizes SMAPI log health at a glance: SMAPI + Stardew Valley versions, loaded mod and content-pack counts, skipped mods (with reasons), failed mods (with reasons, missing dependencies surfaced plainly), and known external conflicts (e.g. RivaTuner Statistics Server). It auto-collapses to a green "All healthy" summary when there are no problems and expands to list issues when some are found. An orange badge flags a stale log when `SMAPI-latest.txt` predates the current StarHubFR session (i.e. no game launch logged since the app opened), shown with a relative timestamp, and an "Open SMAPI log in Finder" button reveals the file. Backed by a new pure, unit-tested `SmapiDiagnostics` parser (Core target) mirroring `SMAPILogDoctor` output; mod update alerts stay on the separate Updates tab.
- **Tooltips on icon-only buttons** — the icon-only buttons across the app now show a localized tooltip on hover explaining what they do: Mods list pagination (previous/next page), window back/forward navigation, Saves view-mode (list/grid) + reload + expand/collapse + close editor + clear inventory slot, install-preview mod details, save-timeline edit-note + delete-backup, and the Logs clear-search button. (11 new tooltip strings, en/fr; `InfoPopoverButton` was deliberately skipped since it already surfaces help via a popover.)
- **Logs tab: clearer app activity + destructive-action guard** — StarHubFR now logs previously-silent user actions in the user's language: app startup ("StarHubFR started", previously the stale "StarHubTH started"), profile creation (name + mod count) and deletion, and Nexus download success/failure (only the start was logged before). "Clear logs" in the Logs tab now asks for confirmation before wiping, and clarifies that only StarHubFR entries are removed (SMAPI entries are kept).

### Changed
- **"Logs" is now "Diagnostics & Performance"** — the sidebar entry name reflects what the tab has become: a health card that explains your SMAPI log, not just a stream of lines.
- **The diagnostics card is readable at a glance** — it had grown into eight sections stacked with identical spacing, everything between 9 and 12pt, with no way to gauge the situation without expanding and counting entries by hand. The header now carries the verdict: status, versions, and a strip of counts per severity (won't load / missing / to watch / harmless). Each section became its own tinted card with a severity rail and an icon chip, colour-coded by how much it matters — a skipped mod no longer looks like a console-access note. Per-mod actions are grouped into one control with proper hit targets, raw log excerpts sit in their own inset block, and suggestions are numbered in priority order. The expanded card takes two thirds of the view and no longer blends into the log list behind it.
- **Logs tab: faster rendering + leaner filter bar** — the source and level filters are merged into one row (was three stacked bars), reclaiming vertical space for the list. Filtering is now single-pass (one pass per render instead of ~9 recomputed filter passes), and the list moved from `List` to a lazy stack — opening the "All" tab no longer spins the wait cursor for several seconds on large SMAPI logs (the previous `List` built/measured all ~2000 rows instead of virtualizing).
- **Logs tab surfaces severity at a glance** — StarHubFR's own log entries are now colored by level (badge + message), so an app error/warning is no longer indistinguishable from an info entry; SMAPI TRACE entries are dimmed to stay readable. The level filter pills now carry per-level count badges (scoped to the selected source), the app source tab is labeled "StarHubFR" (was the stale "StarHubTH"), and "Reload SMAPI log" now replaces the previous snapshot instead of relying on a manual clear.

### Fixed
- **Startup warnings and errors were missing from the Logs tab** — they were counted and explained in the diagnostics card, and plainly present in `SMAPI-latest.txt`, but absent from the list. The card parses the whole file while the list capped at 2000 entries by keeping the *last* 2000 — and SMAPI writes its entire diagnostic at startup, at the top of the file. On a 4038-line log that discarded the first 2038 lines, holding 174 WARN/ERROR/INFO entries. Trimming now sheds TRACE noise instead of the head of the log, so every warning and error survives (measured on the same log: 3 kept before, 11 after — all of them).
- **Clicking a mod name in the log showed the full mod list** — the click switched to the Mods tab but the list arrived unfiltered, because the request was handled by a view that doesn't exist until that tab is open. It now travels through the ViewModel, so the list scopes itself to the mod on arrival, clearing any filter that would exclude it.
- **"Reload SMAPI log" wiped the StarHubFR log** — reloading appended up to 2000 SMAPI entries then trimmed the combined list from the front, which evicted the StarHubFR (app) entries whenever the SMAPI log was large. The cap is now budgeted per source, so app entries are never evicted.
- **Copied log lines lost their origin and mod** — "Copy line" / "Copy all" now include the source (StarHubFR/SMAPI) and the mod name: `[ts] [Source] [LEVEL] Mod: message` (mod prefix omitted when absent).
- **TRACE level label leaked "SMAPI"** — the internal level case (rawValue "SMAPI") was renamed `.trace` (`"TRACE"`), so copied TRACE lines read `[SMAPI] [TRACE]` instead of the confusing `[SMAPI] [SMAPI]`; the TRACE level pill is also now hidden on the StarHubFR source (app entries are never TRACE).
- **Duplicate SMAPI log entries piled up on every game launch** — `startSmapiLogWatcher()` (called after each launch path) routed to `loadSmapiLog()` → `parseAndAppendSmapiLog()`, which appended the full `SMAPI-latest.txt` without clearing or dedup, so N launches left N stacked copies in the Logs tab. Fix: `parseAndAppendSmapiLog` now replaces the existing `.smapi` entries (reload semantics) before appending. Also removed the dead `logOutput` buffer (written app-only, never read) and simplified `appendLogEntry`/`log()`.
- **Launch splash progress bar looked frozen / teleported** — `launchProgress` is published as a few discrete weights (0.05 → 0.15 → 0.25 → …) with real wall-clock gaps between them, so the bar snapped between weights then sat still during the registry decode and the folder-repair sweep (which runs before per-mod names stream), giving the impression of a frozen bar that jumped straight to ~15 %. It also briefly regressed at the end of the scan: clearing `scanProgress` before advancing `launchProgress` to the scan-end weight snapped the bar back to the scan-start value. Fixes: (1) the overlay's progress block is now a self-contained `LaunchProgressBlock` whose bar *creeps* toward its target on a timer — always moving, even mid-gap, never teleporting; (2) `scanMods` publishes an early `(0/N)` frame ("Preparing mods…") before the repair sweep so the count + caption show during that phase instead of nothing; (3) `launchProgress` is advanced to the scan-end weight before `scanProgress` is cleared, so the bar no longer dips at the end of the scan.
- **Multi-component mod packs installed as separate mods instead of one pack (e.g. Lilybrook)** — `ModZipInstaller.detectZipStructure` classified any zip with more than one manifest folder as `.multiMod`, and `buildInfo` then used only the last path component as each component's install destination (`destFolderName = lastPathComponent`), discarding the shared parent folder. A pack like Lilybrook (`[CC]`, `[CP]`, `[FTM]` under one `Lilybrook/` folder) was therefore extracted as separate top-level folders under `Mods/`, and since the scanner only groups mods nested under a single top-level folder, it appeared as individual mods. Fix: in the `.multiMod` branch, when every component shares one top-level parent, preserve it (`Mods/<Parent>/<leaf>`) via a new `commonParent(of:)` helper so the scanner groups the pack into a single entry; flat collections (no shared parent) keep the existing one-folder-per-component behavior. Also fixes a related defect: a bundled dependency shipping its own nested manifest (e.g. `MyMod/lib/SomeDep/manifest.json`) was yanked to a separate top-level mod folder — a manifest folder nested under another manifest folder is now ignored during structure detection.

## [1.9.1] - 2026-07-28

### Changed
- **Default Nexus auto-check setting set to true** — `autoCheckNexusUpdates` now defaults to `true` (using `UDKey.autoCheckNexusUpdates` in `SettingsView.swift` and `StarHubTHViewModel.swift`), enabling automatic Nexus update checks at startup when an API key is saved.
- **Dot-prefix mod toggle (Mods/.X = disabled)** — toggling a mod no longer moves its folder between `Mods/` and `Mods_disabled/`. Instead, a disabled mod is renamed in place inside `Mods/` with a leading dot (e.g. `Mods/CJBCheats` ↔ `Mods/.CJBCheats`), which SMAPI ignores natively. The toggle is now an atomic same-parent rename (O(1)) instead of a cross-folder move, eliminating the brief UI freeze on large mods. `ModItem.folderName` stays logical (never dotted) so the install registry, profiles, activation timestamps and backups are unchanged.
- **One-way migration on first launch** — on the first launch of this version, any mods in the legacy `Mods_disabled/` folder are moved into `Mods/` as `.X` and `Mods_disabled/` is removed. The install registry, activation timestamps and profiles need **no** migration (they key on the logical folder name, which is unchanged). This is a one-way door: downgrading after this migration loses visibility of disabled mods. A permanent warning surfaces in the log if `Mods_disabled/` is ever recreated (by another tool or a cross-version skip).
- **"Clean disabled mods" now removes `Mods/.*`** — the setting no longer deletes a `Mods_disabled/` folder; it enumerates the top level of `Mods/` and removes every dot-prefixed disabled entry. The no-op and error messages were updated accordingly.
- **Duplicate UniqueID detection scans Mods/ only** — the repairer now detects duplicates between an enabled (`Mods/X`) and a disabled (`Mods/.X`) mod within the same `Mods/` folder, instead of across two folders.
- **Manifest decode cache in the scanner** — `scanMods()` now caches each manifest's decoded JSON keyed by file mtime, so a rescan following a single-mod toggle (which re-stat()s every mod but only one manifest changed) does ~N `stat()` calls and zero JSON decodes instead of N decodes.
- **Instant mod toggle (no rescan)** — toggling a mod previously triggered a full `scanMods()` that re-walks the entire `Mods/` tree (enumerating every file of every mod: ~5 s for ~900 mods) just to reflect one folder's renamed state. The toggle still renames `Mods/X ↔ Mods/.X`, but now flips `isEnabled` in memory and rebuilds the lightweight dependency index instead of rescanning — O(toggled) instead of O(total files). The recursive folder-repair pass is also skipped after a toggle (a rename can't create junk, orphans or X/.X duplicates); it still runs on launch, refresh, install, delete and profile-apply. The index rebuild was extracted into `rebuildDependencyIndexes()` so the full scan and the toggle share it.
- **Faster launch + live scan progress** — the launch scan took ~17 s for large mod collections (~900 mods): the folder-repair pass re-decoded every manifest a second time (via `collectUniqueIds`) on top of the scanner's own decode, and the overlay's progress bar froze at 25 % for the whole "Scanning mods" phase. Duplicate detection now runs O(N) in memory from the already-scanned mods (new `ModFolderRepairer.detectDuplicates(from:)`); `scanMods` calls the repair with `detectDuplicates: false` and computes duplicates after the scan. `_Trash_*` folders are excluded from the top-level scan (quarantined mods no longer appear or pollute duplicate detection) and the unused per-file `isDirectory` prefetch is dropped. While scanning, `scanMods` streams the current mod name + `done/total` (throttled ~12/s) via `scanProgress`, so the overlay refines the bar within the scan slice and shows `NomDuMod (X/N)` instead of freezing.

### Fixed
- **Stale Nexus overview header version reported in updates (e.g. latest version 1 vs 2 on Files tab)** — `fetchModInfo` previously relied solely on the `version` field from `mods/{id}.json`, which can be left outdated by mod authors when uploading new versions (e.g. Mod #49782 showing header version "1" while the Files tab features version "2.0.0"). Fix: `NexusUpdateChecker` now queries `files.json` for the primary Main file (`category_id == 1`), resolving the true latest version of the downloadable file.
- **Mod packs failed to activate / toggle (e.g. Stardew Valley Expanded)** — in `scanEntryForMods`, checking `pathComponents.count > 1` on subfolder relative paths (which are evaluated relative to the top-level folder entry itself, yielding a component count of 1 for 1-level-deep sub-mods) caused multi-mod pack folders to split into individual standalone items instead of grouping under the top-level folder. Toggling any of these sub-mods failed because `performToggle` searched for `Mods/<SubMod>` instead of the actual on-disk folder `Mods/<PackFolder>/<SubMod>`. Fix: pass `topLevelLogicalFolder` to `scanEntryForMods` so all manifests found inside a top-level folder correctly group into a single `isGroup` pack with `folderName` set to the top-level folder.
- **Nexus auto-check was skipped silently at startup** — when `autoCheckNexusUpdates` was disabled or no Nexus API key was set, `checkNexusUpdates` returned silently without feedback. An explicit log message is now recorded explaining why auto-check was skipped (`"Auto-check for Nexus updates skipped (disabled in Settings)"` or `"Auto-check for Nexus updates skipped (no Nexus API key set)"`).
- **Removed invalid server entry in `.mcp.json`** — cleaned up the project `.mcp.json` config file by removing an invalid `github` HTTP server block.
- **Disabled mods couldn't be re-enabled, opened in Finder, or config-edited** — for a top-level disabled mod whose on-disk folder is `.X`, `scanMods()` derived `folderName` from the physical path's last path component, yielding `.X` *with* the dot. Since `ModItem.physicalFolderName = "." + folderName`, every on-disk path then resolved to the non-existent `Mods/..X`: the toggle's `fileExists` guard skipped the rename (so the switch snapped back), "Open in Finder" opened nothing, and the config editor couldn't find `config.json`. Only simple (non-pack) disabled mods were affected — pack children derive `folderName` from a `relativePath` that is already computed against the physical root and never carries the dot. Fix: strip the leading dot when deriving the logical folder name in `parseModFolder`, mirroring the `logicalFolder` stripping `ModFolderRepairer` already did.
- **`build_app.py` failed to compile on macOS 26 / Tahoe** — `swiftc` was invoked directly with no explicit deployment target, so it derived `arm64-apple-macosx26.0` from the SDK and failed with `unable to load standard library for target 'arm64-apple-macosx26.0'`; and even with a pinned target the direct invocation lacked the toolchain env (SDKROOT) that `xcrun` provides. Fix: pin `-target <arch>-apple-macosx14.0` (matching `Package.swift` / `Info.plist`, with host-arch detection so Intel isn't broken) and run swiftc through `xcrun`.

### Added
- **Download spinner on Mod Updates rows** — when a Nexus mod download is in flight (both the Premium in-app download and the free `nxm://` "Mod Manager Download" path), the row's action buttons are replaced by an inline spinner tagged to the specific mod being fetched (`downloadingNexusModId`), instead of just disabling every Premium button. Other rows keep their buttons disabled until the download completes.
- **Mod-list row metadata strip** — each mod row now surfaces a compact metadata line under the category/author/version: shipped i18n language codes (with a green "FR available" badge when `i18n/fr.json` is present), the Nexus last-updated date (relative format), and the local install date (folder modification time). The strip is omitted entirely when none of the values are known.
- **French-translation filter** — a new three-state chip ("Trad. FR" / "FR available" / "No FR") in the Mods toolbar scopes the list to mods that ship (or don't ship) an `i18n/fr.json`. Works with the same AND semantics as the existing config-only and category filters, and resolves packs via their children.

## [1.9.0] - 2026-07-27

### Added
- **Smaller, centered launch splash with hidden menus** — the launch overlay is no longer stretched to fill the entire window. It now renders as a contained card centered on an opaque dark scrim: the cover artwork is capped at 440pt wide (preserving its native 16:9 ratio), with the app name and progress bar stacked below it. Native macOS menus (File / Edit / View / Window / Help) and their keyboard shortcuts are hidden for the duration of the splash via `NSApp.mainMenu = nil`, then restored verbatim once `isLaunching` flips to false — so no Cmd+W / Cmd+R etc. can act on the half-loaded UI. The hide also runs in `onAppear` (not only `onChange`) so the menus are gone from the very first frame.
- **Determinate launch overlay with cover artwork** — the indeterminate spinner shown during cold launch is replaced by a full-window overlay using the project's `nexus_cover_final.png` as background, with the app name at the top and a linear progress bar + localized step label at the bottom. The bar advances through every startup phase so the user sees concrete progress instead of a generic "Loading…":
  1. *Initializing…* (0–5%)
  2. *Loading mod registry…* (5–15%) — warms the in-memory JSON cache
  3. *Scanning mods…* (15–70%) — walks `Mods/` and `Mods_disabled/`, parses every manifest, syncs the registry
  4. *Loading saves…* (70–80%)
  5. *Loading profiles…* (80–90%) — also fetches the Steam user identity and seeds Nexus caches + user overrides
  6. *Ready* (100%)
  The cover image is bundled as a resource by `build_app.py` (no dependency on the source tree at runtime).

### Changed
- **Faster time-to-first-paint** — `StarHubTHViewModel.init()` previously blocked the main thread on ~6 UserDefaults JSON decodes (Nexus updates / categories / extras caches, user overrides) plus a pack-consolidation pass, all before the app window could even appear. All that work now runs on the background launch task (`seedNexusAndUserData`), so the window renders the launch overlay immediately. The Nexus caches, user category overrides, activation timestamps, and profile list are seeded asynchronously and published on the main thread once ready.
- **In-memory cache for the install registry** — `loadInstalledModRegistry` no longer re-decodes the ~100KB JSON blob from UserDefaults on every call. It now memoizes the registry in a thread-safe (NSLock-guarded) instance property, refreshed on every save. Since `effectiveVersion` calls `installedModNexusVersion` once per mod during each scan, this previously triggered 100+ full JSON decodes per scan (~10MB of decode churn). After the fix, the decode runs once per session.
- **Install registry save skips no-op writes** — `syncInstalledModRegistry` now tracks a `didChange` flag and skips the JSON encode + double UserDefaults write when nothing actually changed (the common case of a plain refresh with no install, no delete, no version bump). `saveInstalledModRegistry` also encodes the blob exactly once instead of twice (the primary and backup share the same `Data`).
- **Mod Updates sidebar entry always visible** — the "Mod Updates" item in the sidebar was previously hidden when there were zero pending updates, leaving no way to reach the tab to manually trigger a Nexus check. It is now always visible; the numeric badge is hidden when the count is 0.
- **Sidebar search bar removed** — the search field at the top of the sidebar duplicated nothing useful (the Mods list has its own search) and consumed vertical space. It has been removed along with its `searchText` state and `matchesSearch` helper.
- **Centralized Nexus request builder** — all Nexus API calls now go through a single `NexusRequestBuilder.makeRequest(...)` helper (`StarHubTH/Models/NexusRequestBuilder.swift`), which reads the app version live from the bundle's `CFBundleShortVersionString`. Previously `Application-Version` was hardcoded inconsistently (`"1.0.9"` in `NexusUpdateChecker`, `"1.1.0"` in `NexusDownloader`), making Nexus see two different clients for the same app and producing wrong usage statistics.
- **Centralized UserDefaults keys** — shared keys (`gameDir`, `currentLanguage`, `modProfiles`, `activeProfileId`, `launchProfile`, `closeAfterLaunch`, `chainToggleDependencies`, `installedModRegistry`, `installedModRegistryBackup`) now live in a single public `UDKey` enum (`StarHubTH/UDKey.swift`), replacing 16 raw-string literals across 5 files. Typos are now compile-time errors instead of silent cross-key writes.
- **Shared Nexus UpdateKeys parser** — the `nexus:<id>[@variant]` parsing convention (used to resolve a mod's Nexus id) is centralized in `ModManifest.parseNexusId(fromUpdateKeys:)` (public static). Previously duplicated inline in `StarHubTHViewModel.parseModFolder` and `ModManifest.init`.
- **`LANG=C` enforced on child Processes** — `Process()` invocations that parse text output (notably `/usr/bin/unzip -l` in `ModZipInstaller.uncompressedSize`) now set `LANG=C` / `LC_ALL=C` via a shared `cLocaleEnvironment`. Without this, a non-English user locale would translate the summary line ("3 files" → "3 fichiers") and silently disable the zip-bomb size guard when parsing failed.
- **`[weak self]` on background closures** — four `DispatchQueue.global().async` closures in `StarHubTHViewModel` (`refresh`, `performInitialLoad`, `loadSmapiLog`, `reloadSaves`) now capture `self` weakly, matching the convention already applied to the other 11 sites. Prevents future retain cycles if the VM ever stops being an app-lifetime singleton.
- **No `.allowFragments` when a dict is expected** — manifest.json parsers (`ModZipInstaller.scanFolder`, `ModInstallBackupManager.extractModMetadata`, `ModFolderRepairer.collectUniqueIds`) no longer pass `.allowFragments`, which was redundant (the subsequent `as? [String: Any]` would have failed on a non-object fragment anyway) and masked genuinely corrupt files. `.json5Allowed` is preserved where relevant; `.fragmentsAllowed` is kept on Nexus API responses because mod descriptions embed raw control chars.

### Fixed
- **Nexus UpdateKeys with leading whitespace silently dropped** — `parseNexusId` now trims the key *before* the `hasPrefix("nexus:")` check, so values like `"  Nexus:240"` (previously rejected) resolve correctly. Latent bug in both pre-refactor call sites, surfaced by the new `ParseNexusIdTests` suite.
- **Force-unwrapped `as!` in `CodeEditorView`** — the `scrollView.documentView as! NSTextView` casts in `makeNSView` and `updateNSView` are replaced with defensive `guard let ... as?` so a future AppKit change degrades gracefully instead of crashing.

### Fixed
- **Mods re-flagged as updatable after a non-Nexus install** — when a mod was installed/updated by drag-and-drop, manual folder copy, or any path other than the in-app Nexus download, the install registry never recorded the Nexus version (only the in-app flow called `reconcileManifestVersion`). Mods whose author forgot to bump the manifest Version were therefore permanently re-flagged as updatable, because the update checker kept comparing the stale manifest version against the live Nexus version. The registry is now populated for ALL install paths: `syncInstalledModRegistry` reads the Nexus version from the cached `nexusModExtras` map (keyed by Nexus mod id) on every scan, regardless of how the mod landed on disk.
- **`nexusVersion` lost on update** — when `syncInstalledModRegistry` detected a version change (re-install/update), it rebuilt the `InstalledModRecord` without carrying over the previously reconciled `nexusVersion`, silently dropping it back to `nil` and re-introducing the false-positive flag on the next check. The record now preserves (or refreshes) the known Nexus version across updates.
- **`recordInstalledModNexusVersion` no-op when entry missing** — the function silently returned if the folder wasn't yet in the registry, which could happen when it was called right after an install but before the first scan completed. It now creates the entry instead of bailing.

### Added
- **`NexusRequestBuilder`** — single source of truth for Nexus API URL request construction (`apiBase`, `gameDomain`, `appName`, `appVersion` from bundle, `userAgent`).
- **`UDKey`** — centralized `UserDefaults` keys (public enum).
- **`ParseNexusIdTests`** — 6 new unit tests locking the contract of `ModManifest.parseNexusId(fromUpdateKeys:)` (plain key, case/whitespace tolerance, `@variant` suffix, multi-key selection, zero/negative rejection, nil/empty input).
- **Nexus auto-check toggle in Settings** — a new `Auto-check Nexus updates at startup` toggle lives under the Nexus Mods settings section. When enabled **and** a Nexus API key is stored, the app automatically triggers `checkNexusUpdates(force:)` right after the launch overlay dismisses. The toggle is persisted via `UDKey.autoCheckNexusUpdates` / `L10n.Settings.nexusAutoCheck` with matching `en.json` and `fr.json` strings.

### Changed
- **Splash image enlarged to 640×360** — the launch card's cover artwork now uses a larger contained frame while preserving its native 16:9 aspect ratio (`nexus_cover_final.png` is 1672×941). The progress bar width stays at 400pt, keeping the card visually balanced.
- **Navigation buttons hidden when unused** — the back/forward toolbar buttons are now hidden (`opacity = 0`, animated) when there is no navigation history or forward stack, instead of only being disabled. This removes dead UI chrome from the first frame and from any tab with no history.

## [1.8.0] - 2026-07-26

### Added
- **Automatic mod folder repair** — a new `ModFolderRepairer` runs before every scan, quarantining OS junk files (`.DS_Store`, `__MACOSX`, `._*`, `Thumbs.db`), empty folders, and orphan folders without any `manifest.json` into a timestamped `_Trash_<datetime>/` folder inside the game directory. Nothing is ever deleted; the user can inspect or restore quarantined items manually.
- **Duplicate UniqueID detection** — the repairer detects mods that exist in both `Mods/` and `Mods_disabled/` under the same UniqueID and reports them without auto-resolving (surfaced in a new Quarantine tab).
- **Quarantine tab** — a new sidebar section provides access to the last repair report, an "Open Quarantine Folder" button, and an "Empty to Mac Trash" action that moves all `_Trash_*` folders to the Mac Trash via `NSWorkspace.recycle` with a confirmation dialog.
- **SMAPI error logging** — SMAPI errors detected by `parseSMAPILog()` are now journaled to the app log (level `.warning`). The Journaux tab is now visible to all users and serves as the persistent consultable record of system alerts.
- **Content-diffing for SMAPI error journaling** — the VM tracks the last-logged error set, so only genuinely new alerts are appended to the log across re-parses (no duplicate re-logging when counts fluctuate).
- **Launch spinner overlay** — a full-window `ProgressView` overlay (with localized caption) is shown during the initial mod scan + profile load (`vm.isLaunching`), giving immediate feedback on cold launch instead of a blank window. The scan runs off-main-thread via `performInitialLoad()` and flips the flag once `mods` is published.
- **Per-row spinners for destructive operations** — mod deletion, backup restore/delete, and profile activation now show an inline `ProgressView` on the affected row instead of leaving the UI silent during the (potentially slow) folder operation:
  - **Mod deletion** (`ModListView`): the trash button is replaced by a spinner while `vm.pendingDeleteFolder` matches the row; other delete buttons are disabled concurrently.
  - **Backup restore/delete** (`ModInstallBackupsView`): the global `isBusy` bool is replaced by `busyBackupId: UUID?`, showing a spinner on the in-flight row and disabling the rest.
  - **Profile activation** (`ModProfilesView`): the Activate button collapses to a spinner while `vm.applyingProfileId` matches the row's profile.
- **Profile activation error reporting** — when a profile application has problems (move failures and/or missing mods), the alert now names the affected mods (capped to 8 with a "+N" suffix). Each move failure is logged individually with a localized structured message, and profile entries referencing uninstalled mods are detected and reported as "missing" — instead of being silently skipped.
- **Persistent install-date registry** — a new JSON registry (`installedModRegistry`) records the version and install timestamp of every mod on disk, replacing the unreliable on-disk folder mtime for same-version update detection. The registry is synchronized at the end of every scan (`syncInstalledModRegistry`), so mods added by any means — app installer, drag-and-drop, or manual copy into `Mods/` / `Mods_disabled/` — are automatically tracked. Entries for deleted folders are pruned. When a mod's version changes (update/overwrite), its record is stamped with the current time. The registry is backed by a redundant copy (`installedModRegistryBackup`): if the primary blob is corrupt or missing, it is transparently restored from the backup; if both are unavailable, the registry is fully rebuilt from disk on the next scan and the event is logged.

### Changed
- **Sticky mods header & pagination** (`ModListView`) — the toolbar (scope picker, filters, sort) and the pagination footer are now fixed above and below a scrollable list, mirroring `LogsView`'s layout. Previously the entire view (toolbar + list + pagination) scrolled together.
- **Sidebar reorganized** — the bulky 48px account badge is replaced by a compact `AccountHeaderCard` (macOS System Settings style) that consolidates the user identity, active profile, and key metadata (mods active/total + SMAPI status) into a single card. The floating `SystemStatusFooter` (redundant with the card) is removed. The Logs entry moves into the System section (was floating without a header), and the duplicate Quarantine entry is removed (the conditional badge at the top of the sidebar suffices).
- **Sidebar badge items separated** — "Mod Updates" (Nexus updates + out-of-date mods) and "System Alerts" (SMAPI errors) are now distinct sidebar items with their own accent colors (blue and orange) and dedicated views. The Quarantine item appears only when items have been moved.
- **UpdatesView simplified** — the SMAPI errors section has been moved to its own `SystemAlertsView` with a "View Logs" shortcut to the Journaux tab.
- **Overwrite install preserves nested pack-child location** — when overwriting a mod installed inside a pack group folder (e.g. `PackName/ChildMod`), the installer now preserves the full nested `folderName` instead of dropping the child to top-level.
- **`showDeveloperLogs` AppStorage removed from MainView** — the Logs tab is always visible; the dead `@AppStorage` property on `MainView` was unused and removed.
- **Sidebar labels clarified** — "Mods" → "Gestion des mods" and "Mod Backup Management" / "Gestion des sauvegardes de mods" → "Sauvegardes des mods" (EN: "Mod Management" / "Mod Backups"), for clearer navigation labels matching their content.

### Fixed
- **Same-version mods re-flagged as updatable after install** — `FileManager.copyItem` preserves the source folder's mtime (the modder's packaging date, not the install date), so the update checker's same-version detection (`nexusUpload > folderMtime`) always saw a stale date and re-listed the mod on every check. The install date is now sourced from the persistent `installedModRegistry` (stamped with `Date()` on every install/update), with the folder mtime used only as a fallback for pre-existing mods. The installer also touches the installed folder's mtime to `now` as an additional safety net.
- **Backup/restore now handles nested pack-child paths** — `ModInstallBackupManager.createBackup`, `restoreBackup`, and `registerSetAsideFolderAsBackup` correctly create intermediate parent directories for nested folder names like `PackName/ChildMod`.
- **Install tolerates corrupted missing existing mods** — `ModZipInstaller.install()` catches `.modNotFound` during backup as non-fatal when the existing folder is already gone from disk.
- **Temp file leaks in install** — config snapshot files now have a `defer` cleanup that runs regardless of whether the install completes or fails mid-way.
- **Temp extract dir leak on install failure** — `ModInstallView` now calls `cleanupTempDir` on the error path as well as the success path.
- **Background-thread mutation of `@Published` properties** — the `lastRepairReport` from `ModFolderRepairer` is captured on the background scan thread and published on the main queue alongside `self.mods`.
- **Manifest parsing parity for JSON5** — `ModFolderRepairer.collectUniqueIds` now matches the scanner's reading options (`.json5Allowed` on macOS 12+), so JSON5 manifests are not silently skipped by duplicate detection.
- **Dead localization keys** — `quarantine_empty` and `logs_system_alerts_section` (unused) were pruned to maintain the 590-key parity contract between `en.json` and `fr.json`.
- **Multi-mod pack false-positive updates** — `NexusUpdateChecker` de-duplication now keeps the candidate with the highest version per Nexus mod id, instead of the first alphabetically-encountered child. Multi-mod packs (e.g. Swim Mod) that share a Nexus id via `@variant` UpdateKeys no longer permanently flag a false-positive update because a lower-versioned child was selected.
- **Stale manifest versions no longer cause false updates** — `parseModFolder` now resolves an `effectiveVersion` from the registry's recorded Nexus version when it is newer than the manifest's `Version`. Authors who forget to bump the manifest no longer cause permanent re-flagging, and the manifest.json is never rewritten.
- **Registry stores Nexus version instead of patching manifest** — `reconcileManifestVersion` now records the Nexus version in the `installedModRegistry` rather than surgically editing the user's manifest.json. This removes fragility and unexpected disk writes while achieving the same anti-re-flagging behavior.
- **Registry uses install time instead of folder mtime** — `syncInstalledModRegistry` now stamps new entries with `Date()` rather than the folder's modification date, which `FileManager.copyItem` preserves from the modder's archive packaging and would otherwise trigger a spurious same-version update.
- **One-shot registry migration** — a `registryMigrationV2Done` flag wipes and rebuilds the install registry on first launch after this fix, so existing stale mtime-based entries are replaced with clean `Date()` timestamps and the false-positive cycle is broken exactly once.

## [1.7.1] - 2026-07-25

### Added
- **Config & translation preservation on update** — when updating an installed mod (overwrite + backup), the installer now preserves not only `config.json` and `fr.json` but every supported SMAPI language file (`default.json`, `en.json`, `de.json`, `es.json`, `fr.json`, `hu.json`, `id.json`, `it.json`, `ja.json`, `ko.json`, `pl.json`, `pt.json`, `ru.json`, `th.json`, `tr.json`, `uk.json`, `zh.json`) via the shared `ModConfigFiles.preservable` list. The full mod folder is still backed up before overwrite.
- **Dependency sorting & filter toggle in install preview** — dependencies are now sorted by priority (missing/disabled required → missing/disabled optional → satisfied), and a toggle switches between "problems only" (default) and "show all". A pack with many dependencies no longer buries the critical missing ones.
- **Nexus search menu on missing dependencies** — the install preview's missing-dependency rows now offer the same name/author search menu (by mod name via `?gsearch=`, by author via `/games/stardewvalley/mods?author=`) used elsewhere, replacing the old generic `?terms=` link.
- **Resizable install preview sheet** — the popup is now scrollable as a whole and capped to a reasonable height, so packs with many mods/dependencies/conflicts no longer push the action buttons off screen.
- **RAR archive support** — `.rar` mods are now accepted (drag-and-drop, file picker, and validation). Extraction uses the first available of `unrar`, `unar`, or `7z` (checked at runtime in Homebrew/standard PATH). If none is installed, a clear error message prompts `brew install unrar`.
- **Multi-mod pack with wrapper folder detection** — a zip like `Parchment/` containing `Parchment/` + `[CP] Parchment Example Pack/` (multiple mods under a shared wrapper folder) is now correctly classified as a multi-mod pack. Previously only one mod was scanned and the rest silently dropped.
- **Pack-group conflict detection** — updates of mods installed as part of a multi-mod pack group (whose headers have an empty `uniqueId`) are now correctly detected as conflicts, offering backup/overwrite.

### Changed
- **Nexus missing-dependency search** — clicking a missing dependency now opens a menu offering two distinct searches: by mod name (readable split-camelCase, e.g. `Content Patcher`) or by author (e.g. `Pathoschild`). The author search uses the dedicated Nexus filter (`/games/stardewvalley/mods?author=`) for precise results, and is applied consistently in both the mod list and the dependency tree in the detail pane.
- **Mod list search reverted to real-time** — the 200 ms debounce introduced in 1.7.0 caused perceived input lag; restored the instant real-time filtering of 1.6.0 (the precomputed dependency index keeps per-keystroke cost negligible).
- **Deprecated `onChange(of:perform:)` migrated** — all 8 occurrences across `ModListView`, `LogsView`, `MainView`, and `ModConfigEditorView` now use the macOS 14+ two-parameter `onChange(of:initial:_:)` API, removing all deprecation warnings.

## [1.7.0] - 2026-07-25

### Added
- **Design token system** — introduced `AppDesignCore` (SPM-testable pure tokens) and `AppDesignUI` (SwiftUI fonts/colors) to eliminate magic numbers across the UI. All spacing, radius, and opacity values now go through `AppDesign.Spacing/Radius/Opacity`.
- **Design system tests** — 10 tests in the new `StarHubTHCore` target verifying token values and migration correctness.
- **Accessibility infrastructure** — added `ContrastChecker` (WCAG 2.1 compliant luminance utility in SPM for testability) and 7 new `ContrastCheckerTests`.
- **System status footer** — new compact sidebar bar showing enabled mod count, pending updates, and SMAPI error count at a glance.
- **Empty-state drop zone** — when no mods are installed, the list shows a large visual drop zone rather than plain text.
- **Cached async image loader** — `CachedAsyncImage` replaces the system `AsyncImage` in the mod detail pane, caching fetched mod pictures in `NSCache` to avoid redundant downloads.

### Changed
- **Accessibility labels added** — 17 total `accessibilityLabel`/`Value`/`Hint` calls across `ModListRow`, icon-only buttons, sidebar nav, search bar, `SystemStatusFooter`, and `EmptyStateDropZone` so VoiceOver announces the full UI in French or English.
- **Nexus dependency search aligned** — missing-dependency buttons now use the same `…/search/?gsearch=` format as the dependency tree and present human-readable terms (`Content Patcher` instead of `Pathoschild.ContentPatcher`).
- **LazyVStack reverted in ModSectionGroup** — pagination already caps rows at 15, so `LazyVStack`'s benefit is marginal; switched back to deterministic `VStack`.
- **EmptyStateDropZone hover fill semantics** — `.overlay` replaced by `.background` since the hover tint is a fill behind the content, not on top.
- **Nexus tooltip fixed** — the `info.circle` button on each row now correctly opens the mod details sheet (was pointing to the wrong action).
- **Localized accessibility strings** — all VoiceOver strings now go through `L10n` (e.g. `main_system_status_a11y`), removing hardcoded English accessibility copy.

### Fixed
- **Toggle spinner while enabling/disabling mods** — replaced an `alert(isPresented:)` that showed on every toggle with an inline `ProgressView` tied to `pendingToggleFolder`.
- **Dead code warning for `InstallationError`** — the typed enum was never instantiated; confirmed removed from `Package.swift` and its phantom L10n keys were pruned.

## [1.6.0] - 2026-07-25

### Added
- **Home page banner**: the home page now leads with a full-width Nexus banner, with the **Steam avatar floating on the banner** (overlapping its bottom edge over a solid disc so it reads as one cohesive hero), followed by the username and version — replacing the standalone centered avatar.
- **README banner**: the README is now headed by the banner image, above the badges row.

### Changed
- **Richer mod / pack detail pane**: the detail pane now leads with a **fixed hero** — a full-width illustration banner plus a metadata band showing the mod/pack **name**, its **category tag** (Nexus category or the inferred type), version/author, Nexus & bug-report links, and metadata stacked on the right: **last Nexus update**, **install date**, and the mod's **languages** (detected from its `i18n/` folder, recursing subfolders, with `default.json` counted as English). The **Description / Changelog / Dependencies** tabs stay pinned under the hero while their content scrolls; a **pack now lists its contents** (each child mod + enabled state + version) inside the Description tab, alongside the category and Nexus-id editors.
- **Mod packs now show their latest Nexus version** in the mod list: a pack is a single Nexus mod installed as several sub-mods, whose own manifest versions can differ or lag, so the list previously showed a shared child version or "—". It now displays the pack's latest Nexus version (the Main file / changelog version) once an update check (or a per-mod fetch) has retrieved it.

## [1.5.0] - 2026-07-25

### Changed
- **French is now the default language**: the app launches in French regardless of the system locale (an existing saved language choice is still respected); English is used only when explicitly selected.
- **Language & theme switchers moved to the sidebar**: language (🇫🇷 / 🇬🇧) is now a flag toggle pinned bottom-right of the sidebar, and the app theme (System / Light / Dark) an icon toggle bottom-left — one-click access, both re-localize / re-theme the UI live. The corresponding pickers were removed from Settings (its remaining "Developer" section keeps the developer-logs toggle).

## [1.4.0] - 2026-07-25

### Added
- **Default mod profile on first run**: a fresh install now automatically gets a "Default" profile capturing the current mod setup, so there is always an active profile to work from. It is created once (never re-created if you delete your other profiles) and **cannot be deleted**.
- **Active-profile indicator on the Mods page**: the mod list's filter row now shows which profile is currently applied (a read-only accent chip), so you always know the context you're editing in.
- **Install Backups moved to its own sidebar section**: the automatic pre-install / pre-update / pre-restore backups now have a dedicated **Install Backups** sidebar entry (a redesigned `ModInstallBackupsView`) — card-style rows with a reason badge, a backup count, icon-only restore/delete buttons, and a clearer empty state — instead of being reachable only from a button inside the install sheet. The view also spells out the **backup retention policy** (kept up to 30 days, plus the most recent backup per calendar month for longer history, always keeping at least the 5 most recent).

### Changed
- **Mod Profiles page redesigned**: profile actions now live directly on each row instead of behind an info-button detail sheet. Each row shows its **mod count** and a clear **"Active" badge**; an **Activate** button switches to a profile, **Manage mods** applies it and jumps to the Mods page to edit it (replacing the redundant in-sheet mod checklist that duplicated the main mod manager), and a **⋯ menu** (also right-click) offers **Rename** and **Delete**.
- **Safer profile activation**: the profile row is no longer one big tap target that silently switched profiles (which moves mod folders on disk) — switching now requires an explicit button. Activation is **serialized** (the Activate/Manage buttons disable while another profile is still being applied) and **exclusive** (only one profile active at a time). Deleting a profile now asks for confirmation.
- **Mod install window polish**: the install sheet gained a close (✕) button, and its drop zone is now **clickable to browse** for a `.zip` (in addition to drag-and-drop); the redundant "Manage Backups" button was removed from its header.
- **Sidebar reorganized**: the **Thai Translation Hub is now hidden by default** (behind a toggle) to declutter the bilingual app, game-related items were reordered (Profiles before Saves), and several sidebar labels were clarified ("Saves" → "Game Saves", "Config Backups" → "Configuration Backups", "Manage Backups" → "Mod Backup Management").

### Fixed
- **Profile data loss**: applying a profile no longer sweeps mods that have no manifest `UniqueID` into `Mods_disabled`. Profiles key on `UniqueID`, so such mods could never be "covered" and were silently disabled on every profile switch — they are now left untouched.
- Removed a dead "Help" button on the profile detail (its click did nothing).

## [1.3.0] - 2026-07-24

### Changed
- **Mod list toolbar redesign**: the flat single-row toolbar is split into a **two-tier layout** for clearer visual hierarchy — the scope segmented picker (All / Enabled / Disabled / Issues) and primary actions (bulk toggle, install button) sit on the top row, while secondary filters (sort, config-only toggle, category picker) are grouped below with visual dividers so they read as a single "refine the list" unit.
- **Pagination redesign**: the clunky text-field "go to page" input is replaced by **numbered page buttons** with smart ellipsis logic (first, last, current, and neighbors shown; gaps collapsed with "…"). The current page is highlighted in accent color. Removed the now-dead `pageJumpDraft` state and `commitPageJump()` helper.
- **Mod list row UX overhaul** (`ModListView`): each mod row now carries a colored **status accent bar** on its left edge (green = enabled, muted = disabled) for instant at-a-glance scanning, and disabled mods are **visually dimmed** (content opacity reduced to ~72%, name in secondary color, inline status dot) so active mods naturally draw the eye first. The toggle's tint changed from blue to green to match the new accent, and **hover** now shows a tinted fill with a subtle accent focus ring instead of a flat gray wash.
- **Version badges**: mod versions are now displayed in a compact monospaced pill (`VersionBadge`) instead of bare text, making them stand out as distinct scannable units in the metadata row.
- **Dependency warnings restyled**: missing/disabled-dependency warnings now appear in a tinted red box with a border, and disabled dependencies are shown in **orange** (vs. red for missing) for clearer severity distinction.
- **Link cursor fix** (`ViewExtensions`): `.pointingHandCursor()` now uses `onContinuousHover` instead of `onHover`, so the pointing hand correctly persists over links inside `.textSelection(.enabled)` description text (the hosted NSTextView was re-asserting the I-beam cursor on every mouse move).

## [1.2.0] - 2026-07-24

### Added
- **Bulk enable/disable all mods**: a power-button menu in the mods toolbar lets you enable or disable every installed mod at once, with a confirmation dialog.
  - A **full-screen progress overlay** (determinate progress bar + done/total counter) blocks the list during the operation, keeping the UI responsive by running all file moves on a background queue.
  - **Lossless moves**: each move uses a stale-duplicate-aside safety pattern — if a move fails, the destination is restored, so no mod can ever end up lost from both `Mods/` and `Mods_disabled/`. Individual toggles are blocked during the operation to prevent concurrent folder races.
- **Delete mod / mod pack**: a trash button on every mod row (and a context-menu entry) permanently deletes a mod from disk after a per-row confirmation dialog. Packs show a dedicated message clarifying that all child mods are deleted together. Fails with a user-visible alert if the folder can't be removed.
- **Rich mod detail pane**: the small mod-info popover is replaced by an inline detail pane (in the detail column, reached from the mod's info button) with **Description / Changelog / Dependencies** tabs.
  - **Rich description rendering**: the full Nexus description is rendered as native text — BBCode/HTML converted to **bold**/italic/lists/links (with a pointing-hand cursor on links), inline images shown at their **native size** (never upscaled/blurred), collapsible **spoilers** (which now render their own images and formatting), and `[hr]`/`[line]` shown as real dividers. The parser strips *every* stray/unknown tag (not just a whitelist) so no raw BBCode leaks onto the screen, collapses large blank-line runs, and drops meaningless empty/punctuation-only emphasis.
  - **Complete changelog**: pulled from Nexus's dedicated all-versions changelog endpoint (not a single file's changelog), newest version first.
  - **Fast & offline-aware**: raw description/changelog are file-cached and shown instantly on reopen, then refreshed in the background; offline (or no API key) falls back to the local manifest description. Mod **packs** resolve to their first child with a Nexus id so the pane still shows content.
  - The **category override editor** and a **Nexus mod-id editor** (with on-save metadata fetch) moved from the old popover into the pane's settings section.
- **Transitive dependency tree** (mod detail pane, Dependencies tab): the flat dependency list is replaced by an interactive, indented tree showing dependencies-of-dependencies (cycle-safe), with each entry resolved to its installed mod's name/author and a three-state status (enabled / installed-but-disabled / missing). Per-row actions: **Enable** a disabled dependency, open an installed one on **Nexus**, or **Search Nexus** for a missing one; clicking an installed row opens that mod's own detail pane. Content packs now resolve their framework dependency correctly (the manifest's `ContentPackFor` is read alongside `Dependencies`), which also sharpens the Issues filter.
- **Offline mod type tags**: each mod is auto-classified into a type (UI, Framework, Content Patcher, Translation, Cosmetic, NPC, Audio, Map, Gameplay, …) inferred from its manifest — shown as a badge and filterable. Used as an **offline fallback** for the category filter: mods with no Nexus category are now grouped under their inferred type instead of a single "uncategorized" bucket. Ported from upstream, localized (en/th/fr).
- **Launch Game button** (Home page): starts Stardew Valley directly from StarHubFR using the launch profile configured in Settings (SMAPI or Vanilla), with the active profile shown beneath the button — wiring up launch logic that previously existed in the code but was never reachable from the UI.
  - Install-type aware: Steam installs launch through Steam (`steam://run/413150`), while direct/GOG installs run SMAPI's in-place launcher (`StardewValley`) directly. Previously the launch always routed through Steam whenever Steam was installed at all, which hijacked direct/GOG launches (Steam opened but the game never started).
- **Mod Config Editor** (`ModConfigEditorView` / `CodeEditorView`): Edit a mod's `config.json` directly from the app, opened via the "Code Editor" entry in a mod's context menu.
  - Hierarchical **visual editor**: settings are parsed into a searchable tree of typed rows (boolean, string, number), grouped by their nesting path, with an inline search bar to filter by key.
  - **Raw JSON editor** tab: a line-numbered, monospaced code editor (`CodeEditorView`, an `NSViewRepresentable` text view) for direct JSON editing, with live validation and an invalid-JSON warning.
  - **Reset** button (revert unsaved edits) and **Restore Config** button (roll back to a local `config.json.bak`, or pick another `.json` file to restore from), independent of the existing `ModConfigBackupManager` history reachable from the "ConfigBackups" tab.
- **In-App Changelog Viewer** (`AppChangelogView`): New sidebar entry rendering this `CHANGELOG.md` inside the app itself (lightweight Markdown: headings, bullets, inline emphasis), bundled into the app resources at build time.
- **Mod List Toolbar Rework**: the Install button moved from its own row to the right end of the filter row and renamed "Install mods"; the sort menu gained Name (Z-A), Author, and Version options (its button icon is now fixed instead of changing per selection); a new "With Config" filter scopes the list to mods (or packs with a qualifying child) that have a `config.json`; each configurable mod's row now shows a gear icon opening the config editor directly, matching upstream's discoverability while keeping the existing right-click "Code Editor" entry as a second access point.
- **Full French Localization** (`assets/fr.json`, 496 strings): French added as a third supported app language (alongside English and Thai), selectable in Settings and prioritized as the default for French-locale systems — matching this fork's own name (StarHubFR).
- App renamed to **StarHubFR** in the version string shown on the Home page.
- App Info's Developer row now credits **mrbabilo** for this fork's development, alongside **AppleBoiy** for the original app.
- **In-App Nexus Downloads** (on the **Mod Updates** page — the mod-update panel, previously mislabelled "Software Update"): Download mods directly from StarHubFR, complementing (never replacing) manual drag-and-drop install. Both paths feed the existing install pipeline (`ModZipInstaller`), which shows the conflict preview before installing:
  - **Premium update** — an in-app button that fetches the file directly (requires a Nexus Premium account for a direct download link; a clear message points free users to the Nexus path otherwise).
  - **Nexus update** — opens the mod's **Files** tab on Nexus, where the free green "Mod Manager Download" button hands the app an `nxm://` link; the app downloads the file and opens the install preview. The app now uses a single `Window`, so repeated `nxm://` links always route into the existing window instead of stacking new ones.
  - The **Mod Updates** list drops a mod as soon as you install its update (and won't re-list it on next launch), and orders mods most-recently-updated first.
- **Manifest version auto-correction**: after installing a mod update downloaded from Nexus (premium button or free `nxm://`), StarHubFR reconciles the installed `manifest.json` so the mod stops showing a phantom "update available". If the author forgot to bump the `Version`, it is surgically corrected to the mod's Nexus version — the exact version the update checker flags on, so the mod actually clears (only the `Version` value changes — comments/formatting preserved; never downgrades). For a same-version minor update (version unchanged but the Nexus upload is newer), it instead refreshes the mod's modification date so the update checker stops flagging it. Abstains on structured-dict version forms and multi-mod packs.

### Changed
- **App renamed to StarHubFR**: the app now identifies as **StarHubFR** to macOS — Dock, menu bar, Finder, and window title (`CFBundleName`/`CFBundleDisplayName`), and the built bundle and executable are now `StarHubFR.app` / `StarHubFR`. Only the bundle identifier (`com.appleboiy.StarHubTH`) is kept unchanged, to preserve access to the Keychain-stored Nexus API key and existing user preferences.
- **Settings Layout**: the Nexus Mods API key section moved from the bottom of Settings to right after the language picker; its footer now explains that the key is stored in the macOS Keychain, encrypted by the system, and never saved in plain text.
- **Mod Config Backup Manager**: now backs up every language/translation file a mod ships (en/de/es/fr/hu/id/it/ja/ko/pl/pt/ru/th/tr/uk/zh + `default.json`), not just `fr.json` — a backup now captures a mod's full set of localized overrides.
- **Automated test coverage** expanded across `SaveManager` (backup/restore/duplicate/branch folder operations), `ModConfigBackupManager`, and `ModInstallBackupManager` (created/restore/delete/cleanup-retention paths), using Swift Testing against a dedicated SPM package (`Package.swift`) — including a same-second backup-folder-name collision fix and a `listBackups` parsing fix uncovered while writing the new coverage.

### Removed
- **Thai UI language**: Thai is no longer a selectable app language — its translations (`assets/th.json` / `th.lproj`) and the Thai README (`README_TH.md`) were removed, leaving the app **bilingual (English / French)**. The **Thai Translation Hub** (browsing/tracking Thai translation mods) is unchanged. Existing users set to Thai fall back to French (French-locale systems) or English.

### Fixed
- **SMAPI Installer — installation was completely broken.** Two compounding issues, both root-caused against SMAPI's actual current distribution:
  - The hardcoded download endpoint (`smapi.io/get/latest`) no longer exists (confirmed: bare HTTP 404, no redirect). Fixed by resolving the current release dynamically through the GitHub Releases API instead, so this can't go stale again on future SMAPI versions.
  - Even after the download was fixed, installation still failed: SMAPI's packaging changed from a flat `internal/mac/payload` folder (which this app used to copy file-by-file) to a real installer program (`internal/macOS/SMAPI.Installer`) that decides internally which files go where and under what names — not something recoverable from the zip's structure alone. `install()`/`uninstall()` now run this official installer directly (non-interactively, via its stdin prompts) instead of reimplementing its file placement by hand. This also fixes `uninstall()` leaving orphaned `StardewModdingAPI*` files behind, which the old manual/local removal never accounted for.
- **SMAPI Installed Version Display**: `getInstalledVersion()` relied on `smapi-internal/manifest.json`, which no longer exists in SMAPI's current packaging, so the version shown right after installing stayed a generic "Installed" with no number until the game had been launched once. `install()` now records the exact release tag it downloaded, and the version display reads that back first.
- **Mod List Pagination**: toggling the new "With Config" filter didn't reset the current page, unlike every other filter — could leave the pagination footer's prev/next buttons in a stale state until the next navigation.

## [1.1.0] - 2026-07-22

### Added
- **Mod Zip Installer** (`ModZipInstaller` / `ZipModInfo`): Install mods by drag-and-dropping `.zip` files directly into the app. Heuristic multi-level structure detection: single folder with `manifest.json` → base folder; multiple folders with `manifest.json` → multi-mod pack; `manifest.json` at root → base = root.
  - Integrity validation: `.zip` extension + ZIP file signature (`PK\x03\x04`) + size limit (< 500 MB) + zip-bomb detection via `unzip -l` uncompressed-size check before extraction.
  - Dependency handling: scans dependencies via `manifest.json`, flags missing ones, suggests enabling installed-but-disabled mods, lists missing mods with Nexus links.
  - Config protection: never overwrites existing mods' `config.json` or `fr.json` (conflict reported instead).
  - Temporary extraction into `/tmp/StarHubTH_<timestamp>/` with conflict preview, then atomic move to `Mods_disabled` after user validation for full rollback.
  - Active-mod update preservation: when updating an already-enabled mod (in `Mods/`), the new version installs directly into `Mods/` to preserve enabled state; disabled or new mods always go to `Mods_disabled/`.
- **Mod Install Backup Manager** (`ModInstallBackupManager`): Automatic backup before overwriting an existing mod installation. Hybrid 3-tier retention: (1) 5 most recent always kept, (2) all backups ≤ 30 days kept, (3) beyond 30 days the most recent per calendar month kept.
- **Mod Config Backup Manager** (`ModConfigBackupManager`): Backup and restore `config.json`/`fr.json` files for enabled mods.
  - New dedicated error case (`.nothingToBackUp`) distinguishing "no enabled mods" from "mods exist but have no config files" — the empty backup folder is removed instead of creating a zero-content entry.
  - `createDirectory` failures are now propagated instead of silently swallowed.
  - Auto-cleanup removes index entries only after confirmed file deletion on disk.
  - Locking around on-disk JSON index prevents lost updates from concurrent create/restore/delete/cleanup calls.
  - Fixed nested folder path flattening for single-mod "pack" folders.
- **Nexus Mods Update Checker** (`NexusUpdateChecker`): Manual check for mod updates via Nexus Mods API (button-triggered, never automatic).
  - API key stored per-user in macOS Keychain (shared/embedded keys banned by Nexus).
  - Update detection: version strictly higher, OR same version but Nexus upload date more recent than local `installedFileDate` (folder modification date).
  - Bounded concurrency (6 parallel requests via `DispatchSemaphore` + `DispatchGroup`) with immediate abort on HTTP 429.
  - Category names (`category_2..27`) now localized instead of silently falling back to English.
- **Nexus Category Mapping** (`NexusCategory`): Full mapping of 26 Nexus Mods categories with localized names.
- **Install Preview View** (`InstallPreview`): Conflict preview screen showing existing vs. incoming files before installation.
- **Mod Install/Config Backups Views**: Dedicated UI for browsing and restoring installation and configuration backups.
- **Complete Localization**: Added 138 missing translation keys across English and Thai (100% key parity, 480 total keys) so every UI label resolves to real text instead of the raw key.
- **French Documentation**: Introduced `README.md` in French as the default project README, with cross-references to Thai (`README_TH.md`) and English (`README_EN.md`) versions.

### Changed
- **SMAPI Installer**: Refactored `install` and `uninstall` to run asynchronously on a background queue (`DispatchQueue.global(qos: .userInitiated)`) with staged progress updates (20% → 60% → 100%) so the caller is no longer blocked.
- **Mod List View**: Major rebuild (`+1135` lines) with category filter menu, pagination (15/page with direct page jump), uncategorized mod filter, mod activation order sorting, and mod description image support.
- **Main Thread Safety**: `fetchSteamUser`, `editSave`, `saveInventory`, and `zipToDesktop` (Settings backup buttons) now perform file I/O off the main thread instead of blocking the UI.
- **Dependency Cascade**: `applyChainToSet`'s disable cascade now only walks through currently-enabled mods, matching `toggleMod`'s equivalent BFS.
- **Save Manager**: Refactored (`+265`/`-` lines) with improved save branching and XML manipulation safety.
- **Thai Translation Hub**: Refactored view for cleaner download logic using GitHub Releases with normalized zip name comparison (handles dots vs. spaces in GitHub asset naming).
- **Toggle Button**: Fixed visual rebound and data-loss race condition during toggling.
- **Nexus Cache Reads**: `hasRecentCheck`/`cachedUpdates`/`cachedCategories`/`cachedExtras` now take the same lock every cache-write path already used.
- **Shared Avatar Component**: Remaining inline avatar-circle implementations in `ModProfilesView` now use the shared `InitialsAvatar` component (already applied elsewhere in this release).
- **Toggle Staleness**: `toggleMod`'s target enable/disable state is now re-derived from the current mod list at execution time instead of the (possibly stale) snapshot captured when the toggle was queued.

### Fixed
- **Nexus Update Checker**: A run that found real data (updates and/or categories/extras) no longer gets collapsed into `.error`/`.rateLimited` just because one other candidate failed or a 429 cut it short — previously discarded already-fetched data.
- **Category Counts**: `availableCategories` now resolves the same way the `.category` filter branch does (top-level mod), instead of counting each group child individually.
- **String Formatting**: 3 sites in `installThaiTranslation` building `"%@"`-template messages via concatenation instead of `String(format:)` now format correctly.
- **SMAPI Message Keys**: Concatenation bug in SMAPI message keys fixed.
- **Localization**: Hardcoded English strings routed through L10n: `build_app.py` codesign return code now checked, Steam Account/Player fallback/None tag and avatar-preset tooltips (previously Thai-only), missing "Profiles" case in `navigationTitleText`, unused `saves_item_id` key now applied.
- **Empty Backups**: Fixed creation of empty backup entries when no `config.json`/`fr.json` files are found in any enabled mod.
- **Index Consistency**: Fixed backup index diverging from disk when file deletion fails during automatic cleanup.
- **Mod Config Backup Path**: Fixed `ModConfigBackupManager` flattening a mod's nested folder path (single-mod "pack" folders resolved to the wrong phantom location).
- **Temp Directory Leak**: Fixed temp-dir leak on mid-analysis sheet dismissal and guarded against dropped zip destroying in-flight temp directories.

## [1.0.9] - 2026-07-18

### Fixed
- **Thai Translation Hub**: Fixed a bug where Group Mods were not correctly evaluated as installed. The app now recursively checks sub-folders (children) of group mods for the `th.json` translation file.
- **Thai Translation Hub**: Enhanced the UI by removing the confusing yellow warning triangle icon for installed translations, and updated the localized text to a positive confirmation message.

## [1.0.8] - 2026-07-08

### Added
- **Inventory Editor**: Added a new section in the Save Editor to view and modify player inventory items.
  - Safely edit stack amounts for items.
  - Delete items directly from your inventory.
  - Implemented safe XML manipulation using `XMLDocument` to prevent save file corruption.

### Fixed
- Fixed an issue in `StandardSection` where excessive padding caused large gaps between UI rows in Settings and App Info pages.

## [1.0.6] - 2026-07-04

### Added
- **SMAPI Log Viewer v2** — Logs page fully rebuilt:
  - **Source tabs**: Clearly separates StarHubTH app logs from SMAPI logs. Switch tabs to view only the source you need.
  - **Level filter pills**: Filter by INFO / WARN / ERROR / TRACE at any time. Works in combination with source tabs (e.g. SMAPI + WARN = only SMAPI warnings).
  - **Structured log entries**: Each entry carries a level, real SMAPI timestamp (HH:MM:SS), message, source, and mod name.
  - **Continuation line merging**: SMAPI log lines without a `[` prefix (continuation lines) are automatically merged into the previous entry.
  - **Reload button**: Reload `SMAPI-latest.txt` at any time without clearing app logs. SMAPI buffers and flushes in batches, not line-by-line.
  - **Clear app logs**: "Clear Logs" button removes only app-generated entries, leaving SMAPI log intact.
  - **Search bar**: Real-time search across message text and mod names.
  - **Clickable mod name badges**: Mod names in SMAPI log entries are clickable — navigates to the Mods page and highlights that mod.
  - **Copy button**: Copies all currently filtered entries to the clipboard.
  - **Auto-scroll toggle**: Opt in or out of auto-scrolling to the latest entry.
  - **Status bar**: Shows filtered entry count vs. total.
  - **Context menu**: Right-click any entry to copy that line.
  - **Color coding**: Red (ERROR), orange (WARN), blue (SMAPI/TRACE), default (INFO/app).
- **Centralized JSON Localization Source**: Added `assets/en.json` and `assets/th.json` as the source of truth for UI text. `build_app.py` now regenerates `Localizable.strings` from these files and fails if Thai/English keys do not match.

### Changed
- `LogEntry` now has a `source` field (`.app` / `.smapi`) to distinguish log origin.
- `log()` in ViewModel always sets `source: .app`.
- `loadSmapiLog()` sets `source: .smapi` and parses timestamps directly from the SMAPI format `[HH:MM:SS LEVEL  Context]`, including double-space handling. SMAPI buffers log output and flushes it in batches rather than line-by-line, so the Reload button may need pressing again after closing the game to see the complete log.
- Removed Japanese localization and the Japanese language picker option. The app now supports English and Thai only.
- Unsupported or removed saved language values now normalize to a supported language, preferring Thai when the user's system language is Thai.
- Thai save-branching terminology now uses "สร้างเซฟใหม่" instead of "แตกสาขา".
- `build_app.py` now uses a project-local Swift module cache so local builds work without writing to the user-level compiler cache.

### Fixed
- Fixed Thai season names appearing inside the English Saves list by making save seasons use centralized localization keys.
- Fixed nested save branches disappearing from the parent-child Saves tree by rebuilding the hierarchy recursively from detected parent folders instead of using a single-level `_copy` / `_branch` regex.
- Fixed mixed-language Backup Timeline labels by localizing backup, restore, branch/create-save, relative time, and date display through the selected app language.
- Fixed several remaining hardcoded Save/Settings/Logs/Mod List strings so Thai and English translations stay in sync.

## [1.0.5] - 2026-07-04

### Added
- **Typed Localization System (L10n)**: Replaced all raw Thai string keys with a typed `L10n` enum. Every UI string now goes through `vm.L(L10n.Section.key)` — compiler will catch missing or mistyped keys instead of silently falling back.
- **Auto-toggle Dependencies Setting**: Added a new "Mod Behavior" section in Settings with a toggle to enable/disable automatic dependency chain toggling. When enabled, opening a mod also enables its required dependencies, and closing a mod closes mods that depend on it. Can now be turned off for manual per-mod control.
- **Mod Profile Improvements**:
  - Profile detail sheet now reflects actual filesystem state when the active profile is opened (no more "0 mods" display).
  - Creating a new profile now snapshots currently enabled mods automatically instead of starting empty.
  - Profile checkbox list now groups mods the same way as the main Mod List page (groups stay grouped instead of being flattened).
  - Checking a mod in a profile now respects the "Auto-toggle Dependencies" setting — checking one mod can cascade-enable its dependencies.
  - Toggling mods on the main Mod List page now syncs the active profile's stored list automatically.
  - Fixed a critical bug where group mods (e.g. Eli & Dylan with 15 sub-mods) were incorrectly matched by `uniqueId = ""` in `applyProfileToFilesystem`, causing only standalone mods to apply correctly. Groups now match by checking if any child is in the enabled list.
  - `updateProfile` (OK button) now correctly applies changes to the filesystem when editing the active profile, instead of being overwritten by a sync from the old filesystem state.
- **Core Extensions — 3-State Status**: The Core Extensions section on the Home screen now distinguishes between three states:
  - ✅ Green: Installed and enabled
  - 🟠 Orange: Installed but disabled
  - ❌ Red: Not installed
- **Core Extensions — Author & Version**: Each core mod row now shows the author name and installed version when the mod is found on disk.
- **Core Extensions — SVE**: Added Stardew Valley Expanded (SVE) to the Core Extensions tracking list.
- **English README & Nexus Description**: Added `README_EN.md` and `nexus_description_en.txt` for international users. Added `[!IMPORTANT]` callout at the top of the Thai README linking to the English version.

### Changed
- `smapiInstalledVersion` changed from `String` (using a Thai sentinel string) to `String?` (`nil` = not installed) — removes a fragile string comparison from business logic.
- `SmapiInstaller` status messages now use `L10n.Smapi` keys instead of `String(localized:)`, ensuring they go through the same runtime language bundle as the rest of the app.
- `applyChain` in `ProfileDetailSheet` now delegates entirely to `vm.applyChainToSet(mod:enable:currentEnabled:)` in the ViewModel — single source of truth, guaranteed identical behavior between the Mod List page and the Profile detail page.

### Fixed
- Fixed profile mod count showing 0 on re-open by loading from actual filesystem state for the active profile in `onAppear`.
- Fixed `applyProfileToFilesystem` not moving group mod folders because `uniqueId` for groups is always `""`.
- Fixed `syncActiveProfileIds` being called after `applyProfileToFilesystem` overwrote the newly saved `enabledModIds` with the old filesystem state.
- Fixed sidebar section headers being re-translated via `LocalizedStringKey` after already receiving a translated string — headers now use `Text(string)` directly.
- Fixed hardcoded Thai strings in `SaveEditorView`, `SettingsView`, `ModListView`, `MainView` alert, and `toggleMod` log messages.

## [1.0.4] - 2026-07-04

### Added
- Added **Mod Profiles** feature: Create, switch, and delete multiple mod profiles to manage different mod setups easily.
- Added a Profile Indicator badge next to the Steam avatar on the Home screen to quickly identify the active profile.
- Added "Select All" and "Deselect All" buttons in the Mod Profiles management window.
- Added Mod ID (`UniqueID`) support to the Mod List search bar, allowing you to search mods by their internal ID.

### Changed
- **Smart Dependency Management**:
  - When enabling a mod, the app now automatically and recursively enables all REQUIRED dependencies.
  - When disabling a mod, the app now automatically and recursively disables all enabled mods that rely on it, preventing crashes from missing dependencies.
  - This system correctly navigates group folders to find the exact sub-mods involved in the dependency chain.
- Enhanced the Dependency Status Indicator in the Mod Info popup with 3 clear states:
  - ✅ Green Checkmark: Dependency is installed AND enabled.
  - ❕ Orange Exclamation: Dependency is installed BUT disabled.
  - ❌ Red Cross: Dependency is NOT installed.
- Simplified the Mod List toolbar by removing the redundant API status indicator (this status is already available on the Home screen).

### Fixed
- Fixed a major flaw in the mod toggle logic where group folders failed to resolve sub-mod dependencies.
- Fixed the API indicator styling conflict that caused a "double border" glitch due to native macOS toolbar styling.

## [1.0.3] - 2026-07-03

### Changed
- Standardized UI components (Settings/Toggles) to match native macOS aesthetics.
- Replaced custom toggle switches with native macOS `SwitchToggleStyle`.
- Improved UI alignment by allowing components to size naturally and align right in settings.
- Moved search bars and action buttons (like refresh/status badges) to the native macOS Navigation Toolbar.
- Renamed "Game System Info" section to "App Info".
- Added native-style section headers to the Sidebar (e.g., "Game Management", "System Settings", "Online Services") to group menu items logically.

### Fixed
- Fixed app launching to the incorrect default tab (now opens to the Home/Profile page).
- Implemented full Navigation History, allowing the macOS Back/Forward toolbar buttons to correctly navigate through previously visited tabs.
- Reduced sizes of toggle switches and info popover buttons to be properly proportional to the surrounding text.
- Removed redundant English parenthetical texts from localized Thai UI strings.
- Fixed a bug where English and Japanese localizations in the Settings page failed to display properly due to mismatched translation keys.

## [1.0.2] - 2026-07-03

### Added
- Added full **Japanese Localization** (Trilingual Support).

### Fixed
- Fixed a bug where navigation titles and `String(localized:)` did not dynamically update when changing languages in-app.
- Fixed a type mismatch bug that caused save file money to display as corrupted memory addresses when formatted with commas.
- Improved localized format strings in the Saves View to respect native language grammar structures.
- Cleaned up redundant English parentheses in Thai and Japanese UI texts.

## [1.0.1] - 2026-07-01

### Added
- Added partial Thai translation (~41%) for **Sword & Sorcery** by DaisyNiko.
  - ✅ **Mateo** — Core dialogue, Events (0H–14H), Marriage dialogue, Custom Talk (CH2–CH5)
  - ✅ **Hector / Biróg** — Core dialogue, Events (0H–14H) including D&D session, river restoration, and grove revelation; Marriage dialogue; Custom Talk (CH2–CH5 + Other)
  - ✅ **Eyvind** — Chapter 2–4 dialogue (backstory with Mateo)
  - ✅ **Cirrus** — Core dialogue, Festival dialogue (all seasons), Gift reactions, Movie reactions, Resort dialogue, Player Death reactions
  - 🔄 **Cirrus** — Marriage dialogue, Events (0H–10H), Strings (in progress)
  - ⏳ **Dandelion, Roslin, and remaining characters** — Pending
- Updated README.md to include Sword & Sorcery and added full Thai-language README section.

## [1.0.0] - 2026-07-01

### Added
- Initial release of the Thai translation collection.
- Added translation for **UI Info Suite 2 Alternative** (v2.8.32) by DazUki.
- Added translation for **Unlockable Bundles** (v4.3.1) by DeLiXx.
- Added translation for **Wear More Rings** (v7.9) by bcmpinc.
- Added translation for **World Navigator** (v1.4.2) by pneuma163.

[Unreleased]: https://github.com/mrbabilo/StarHubFR/compare/v1.8.0...HEAD
[1.8.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.7.1...v1.8.0
[1.7.1]: https://github.com/mrbabilo/StarHubFR/compare/v1.7.0...v1.7.1
[1.7.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/mrbabilo/StarHubFR/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/mrbabilo/StarHubFR/compare/e38c4eb...v1.1.0
[1.0.9]: https://github.com/mrbabilo/StarHubFR/commit/e38c4eb
[1.0.8]: https://github.com/mrbabilo/StarHubFR/commit/b367896
[1.0.6]: https://github.com/mrbabilo/StarHubFR/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/mrbabilo/StarHubFR/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/mrbabilo/StarHubFR/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/mrbabilo/StarHubFR/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/mrbabilo/StarHubFR/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/mrbabilo/StarHubFR/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/mrbabilo/StarHubFR/releases/tag/v1.0.0
