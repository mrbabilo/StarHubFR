# D2-T4 — Session diagnostique SLO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter à Performances un diagnostic SLO temporaire, récupérable et analysé, avec proposition d’installation quand SLO manque.

**Architecture:** Trois unités Core séparent disponibilité, transaction disque et interprétation des mesures. Un store `@MainActor @Observable` orchestre lancement, reprise et restauration par un adaptateur de gestes existants ; une vue dédiée ne fait aucun calcul. Journal SLO et fichiers sonde sont corrélés par une borne persistée avant lancement.

**Tech Stack:** Swift 6, SwiftUI, Observation, Foundation, CryptoKit, Swift Testing, macOS 14+.

**Spec:** `../specs/2026-10-06-d2-t4-diagnostic-slo-design.md`

## Global Constraints

- Travailler sur `main`, sans ajouter d’état au `StarHubTHViewModel`.
- macOS 14+, Swift 6 ; aucun nouveau package ou service réseau.
- Toute requête Nexus passe par pipeline existant et `NexusRequestBuilder`.
- Tout chemin de mod utilise `physicalFolderName`; désactivation par renommage pointé même-parent.
- `config.json` exige une racine objet ; jamais `.allowFragments`; JSON5 accepté.
- Les deux seules clés temporaires sont `EnableDetailedDiagnostics` et `EnablePerformanceMeasurement`.
- Mutations observables sur MainActor ; I/O et parsing volumineux hors MainActor.
- `assets/en.json` et `assets/fr.json` gardent exactement mêmes clés ; `.strings` jamais édités.
- Boutons lisibles à 560 pt via `AdaptiveLabels`; animations <= 150 ms et Réduire les animations respecté.
- Aucun journal réel, chemin personnel ou contenu de configuration copié dans fixtures.
- Agent ne lance jamais application et ne prend jamais capture.

## Review Focus

1. `SMAPI-latest.txt` remplacé ou tronqué au lancement : rapport doit lire nouveau journal, jamais session précédente — Task 4, tests `replacementLogStartsAtZero` et `unchangedLogProducesNoSession`.
2. SLO ou sonde au sein d’un groupe, dossier pointé ou UniqueID dupliqué : chemin physique correct ou refus ambigu — Task 1, tests `findsPausedNestedInstallation` et `duplicateUniqueIdIsAmbiguous`.
3. SLO normalise `config.json` au lancement : accepter seulement empreinte attestée ; toute autre modification refuse écrasement — Tasks 2/5, tests `attestedNormalizationRestores` et `changedDiagnosticFileRequiresResolution`.
4. Notification de fermeture manquée ou StarHubFR redémarré : plan présent et jeu fermé déclenche reprise idempotente — Task 5, tests `resumeRestoresClosedSession` et `secondResumeDoesNothing`.
5. Installation Nexus terminée pendant carte ouverte : état se recalcule depuis scan et ne lance jamais jeu — Task 6, test de présentation `installedSloOffersPreparationWithoutAutoLaunch`.
6. Dossier SLO pointé renommé avant écriture : tous chemins initial/actif sont persistés et restauration écrit config avant de repointer racine — Tasks 2/5, tests `pausedRootUsesActiveConfigPath` et `restoreWritesBeforeDisablingRoot`.
7. Lancement accepté mais processus jamais visible : délai 90 s puis restauration ; redémarrage dans ce délai attend sans restaurer trop tôt — Task 5.
8. Session sonde étrangère : inventaire doit contenir SLO et la sonde ; SHA différent n’est accepté qu’après preuve de normalisation SLO — Tasks 4/5.
9. Dernier rapport et exclusion mutuelle survivent au redémarrage : reçu dérivé persistant et instantané consulté par benchmark, bissection et mesure guidée — Tasks 3/5.
10. Volume externe absent ou `X` et `.X` présents ensemble : reprise garde instantané et n’interprète jamais absence disque comme restauration — Tasks 2/5.
11. Crash à chaque frontière transactionnelle : racine/config déjà initiale compte comme restaurée, état temporaire est remis, tout troisième état bloque — Tasks 2/5.

---

### Task 1: Contrat SLO, découverte et route d’installation

**Files:**
- Create: `StarHubTH/Models/SloDiagnosticContract.swift`
- Create: `Tests/SloDiagnosticTests/SloDiagnosticContractTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `ModPresence`, `ModItem.components`, `ModItem.physicalFolderName`, `ProbeLoadRecords.version(_:atLeast:)`, `MissingDependencies.filesPage(nexusId:)`.
- Produces:
  - `SloDiagnosticContract.uniqueId: String`
  - `SloDiagnosticContract.nexusId: Int`
  - `SloDiagnosticContract.minimumVersion: [Int]`
  - `SloDiagnosticContract.detailedDiagnosticsKey: String`
  - `SloDiagnosticContract.performanceMeasurementKey: String`
  - `SloDiagnosticInstallation { rootFolderName, rootPhysicalFolderName, activeRootPhysicalFolderName, componentRelativePath, version, isEnabled, initialConfigURL, activeConfigURL, activatedSiblingNames }`
  - `SloDiagnosticDiscovery` cases `.absent`, `.found(SloDiagnosticInstallation)`, `.ambiguous([String])`
  - `SloDiagnosticCompatibility` cases `.compatible`, `.outdated(String)`, `.missingConfig`, `.invalidConfig`
  - `SloDiagnosticReadiness` cases `.sloAbsent`, `.sloDownloading`, `.sloPaused(SloDiagnosticInstallation)`, `.ready(SloDiagnosticInstallation)`, `.incompatible(String)`, `.ambiguous([String])`, `.probeInstallRequired(ProbeBundle.Action)`, `.probePaused`, `.blocked(String)`
  - `SloDiagnosticInstallRoute` cases `.directDownload(Int)`, `.webPage(URL)`
  - `SloDiagnosticContract.discover(mods:gameDir:) -> SloDiagnosticDiscovery`
  - `SloDiagnosticContract.compatibility(installation:configData:) -> SloDiagnosticCompatibility`
  - `SloDiagnosticContract.readiness(discovery:compatibility:probe:nexusActivity:launchProfile:busyReason:) -> SloDiagnosticReadiness`
  - `SloDiagnosticContract.installRoute(directDownloadUnavailable:) -> SloDiagnosticInstallRoute`

- [ ] **Step 1: Add failing discovery and installation tests**

Create synthetic top-level, paused and grouped `ModItem` values. Assert:

```swift
#expect(SloDiagnosticContract.uniqueId == "neoiw.StardewLoadingOptimizer")
#expect(SloDiagnosticContract.nexusId == 50153)
#expect(SloDiagnosticContract.discover(mods: [], gameDir: "/Game") == .absent)
#expect(found.rootFolderName == "Pack")
#expect(found.rootPhysicalFolderName == ".Pack")
#expect(found.componentRelativePath == "SLO")
#expect(found.initialConfigURL.path == "/Game/Mods/.Pack/SLO/config.json")
#expect(found.activeConfigURL.path == "/Game/Mods/Pack/SLO/config.json")
#expect(SloDiagnosticContract.installRoute(directDownloadUnavailable: false) == .directDownload(50153))
#expect(SloDiagnosticContract.installRoute(directDownloadUnavailable: true) ==
        .webPage(MissingDependencies.filesPage(nexusId: 50153)))
```

Add duplicate UniqueID case, grouped siblings, version boundary `0.9.9`/`1.0.0`,
profil Vanilla bloqué, sonde absente/ancienne/bundle indisponible/version plus
récente, et activité Nexus couvrant à la fois téléchargement et archive 50153 en
attente d’installation.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticContractTests`

Expected: compile failure because `SloDiagnosticContract` and related types do not exist.

- [ ] **Step 3: Implement contract and discovery**

Walk top-level mods and their `components`, but construct disk path from owning top-level `physicalFolderName` plus child-relative suffix. Keep logical root separately for toggles. Return `.ambiguous` instead of choosing first duplicate. Treat missing `config.json` separately from incompatible version; Task 2 can prepare minimal config for compatible SLO.
`missingConfig` reste donc prépar-able pour SLO >= 1.0.0 ; racine/type invalide rend `.incompatible`.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticContractTests`

Expected: all `SloDiagnosticContractTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Package.swift StarHubTH/Models/SloDiagnosticContract.swift Tests/SloDiagnosticTests/SloDiagnosticContractTests.swift
git commit -m "feat(performance): resolve SLO diagnostic availability"
```

---

### Task 2: Transaction de configuration et instantané récupérable

**Files:**
- Create: `StarHubTH/Models/SloDiagnosticTransaction.swift`
- Create: `Tests/SloDiagnosticTests/SloDiagnosticTransactionTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: keys and installation from Task 1; `AppSupport.directory` only through explicit directory parameter.
- Produces:
  - `SloDiagnosticConfigState: Codable, Equatable, Sendable` cases `.missing`, `.bytes(Data)`
  - `SloDiagnosticLogBookmark: Codable, Equatable, Sendable { size: Int, sha256: String, modified: Date? }`
  - `SloDiagnosticSnapshot: Codable, Equatable, Sendable` with `formatVersion = 1`, UUID, `startedAt`, `launchRequestedAt`, `gameSeen`, resolved Mods root, deduplicated logical roots, initial/active physical and config paths, initial states, original and diagnostic config bytes, accepted diagnostic SHA-256 values, log bookmark and known probe session IDs
  - `SloDiagnosticPreparedConfig { data: Data, original: SloDiagnosticConfigState, sha256: String }`
  - `SloDiagnosticRestoreDecision` cases `.restore(Data)`, `.remove`, `.alreadyRestored`, `.conflict`
  - `SloDiagnosticTransaction.prepare(original: Data?, version: String) throws -> SloDiagnosticPreparedConfig`
  - `SloDiagnosticTransaction.restoreDecision(snapshot:current:) -> SloDiagnosticRestoreDecision`
  - `SloDiagnosticSnapshotStore.save/load/clear(..., in directory: URL?)`

- [ ] **Step 1: Add failing config preparation tests**

Tests cover strict scalar refusal, JSON5 comments/trailing comma, unknown nested values, absent file on SLO 1.0.0, old version refusal, invalid existing key type, and exact two booleans enabled. Explicitly accept JSON booleans and reject numeric `0`/`1` despite Foundation bridging through `NSNumber` (`CFBooleanGetTypeID`). Decode output and assert unknown values remain semantically equal; do not assert formatting.

- [ ] **Step 2: Run config tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticTransactionTests`

Expected: compile failure because transaction types do not exist.

- [ ] **Step 3: Implement preparation and SHA-256**

Use `JSONSerialization` with `.json5Allowed`, require `[String: Any]`, refuse non-Boolean existing diagnostic keys, set only Task 1 keys, serialize valid JSON atomically at caller. Use CryptoKit SHA-256 rendered lowercase hex. Empty/missing file becomes minimal object only for compatible SLO.

- [ ] **Step 4: Add failing restoration and persistence tests**

Assert exact rules:

```swift
#expect(decision(current: prepared.data) == .restore(originalBytes))
#expect(decision(current: originalBytes) == .alreadyRestored)
#expect(decision(current: externallyChanged) == .conflict)
#expect(missingOriginalDecision(current: prepared.data) == .remove)
```

Round-trip snapshot in temporary directory, corrupt it, clear twice, and prove tests never touch real Application Support.
Include SLO and Probe nested under the same top-level root: mutation/restoration plan contains that root once.
Exercise snapshot states before launch timestamp, after one root move, after config write, after config restore and after root restore. When a paused root is already restored, inspect `initialConfigURL`; do not treat missing `activeConfigURL` as missing config.

- [ ] **Step 5: Run restoration tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticTransactionTests`

Expected: new restoration tests fail until decisions/store exist.

- [ ] **Step 6: Implement restoration decision and snapshot store**

Compare current bytes to accepted diagnostic SHA values and exact original bytes. Never restore when current content matches neither. Initial accepted set contains only bytes written by StarHubFR; Task 5 may add one SLO-normalized SHA under its stricter evidence rule. Snapshot carries both initial and active paths so a paused `.Pack/SLO/config.json` is read before rename, written/restored at `Pack/SLO/config.json`, then moved back by restoring the root. Store snapshot with `.atomic`; clear only after successful filesystem and mod-state restoration. Caller grants owner write access before diagnostic write and restore, writes atomically, relit bytes and verifies SHA.

- [ ] **Step 7: Run focused tests and verify GREEN**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticTransactionTests`

Expected: all transaction tests pass.

- [ ] **Step 8: Commit**

```bash
git add Package.swift StarHubTH/Models/SloDiagnosticTransaction.swift Tests/SloDiagnosticTests/SloDiagnosticTransactionTests.swift
git commit -m "feat(performance): make SLO diagnostics reversible"
```

---

### Task 3: Parseur et analyse du diagnostic SLO

**Files:**
- Create: `StarHubTH/Models/SloDiagnosticLog.swift`
- Create: `StarHubTH/Models/SloDiagnosticReport.swift`
- Create: `Tests/SloDiagnosticTests/SloDiagnosticReportTests.swift`
- Modify: `StarHubTH/Models/SloOptimizerConfig.swift`
- Modify: `Tests/SmapiLogParserTests/SloOptimizerConfigTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `SloOptimizerConfig`, `ProbeSession`, `ProbeLoadRecord`, `ProbeLoadBreakdown`, `ProbeModCostMinute`.
- Produces:
  - `SloDiagnosticLog.parse(_:) -> SloDiagnosticLog`
  - typed cache/image/prefetch/deferred/SpaceCore/native/hotspot/warp/slow-update records
  - `SloDiagnosticProbeInput { session: ProbeSession?, loads: [ProbeLoadRecord], inventory: ProbeInventoryLaunch? }`
  - `enum SloDiagnosticLimitation: String, Codable, Equatable, Sendable`
  - `SloDiagnosticReport: Codable, Equatable, Sendable`
  - `SloDiagnosticReport.build(log:probe:startedAt:) -> SloDiagnosticReport`
  - report fields `config`, `launch`, `save`, `primaryWait`, `loadScopeMarks`, `mapCache`, `imageCache`, `prefetch`, `deferredTiles`, `spaceCore`, `warps`, `steadyGameplay`, `frameMarks`, `memoryMarks`, `sloRuntime`, `memory`, `readyStalls`, `limitations`

- [ ] **Step 1: Add failing marker parser tests**

Use short anonymous strings modeled on 1.0.0 lines. Cover:

- `[MAP CACHE SNAPSHOT]` with 802 hits/0 misses/0 corruptions;
- `[IMAGE CACHE SNAPSHOT]` with 382.5/384 MB, 1,692 hits, 1,604 misses and 179 evictions;
- complete and incomplete prefetch;
- deferred tile and SpaceCore snapshots;
- 16 completed warps, one abort and one excluded transition;
- repeated cumulative snapshots select latest valid values without summing;
- decimal dot/comma, reordered fields, missing optional field and malformed line.

- [ ] **Step 2: Run parser tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticReportTests`

Expected: compile failure because log/report types do not exist.

- [ ] **Step 3: Implement marker-specific parser**

Parse only known bracket markers. Do not use one comma splitter for every line: nested `top=` lists and localized decimals require marker-specific regular expressions/helpers. Store byte/count counters as `Int64`; reject overflow, non-finite durations and negative physical counters. Unknown/new lines are ignored and later represented by missing fields. Tighten `SloOptimizerConfig.bool` so only case-insensitive `true`/`false` parse; malformed tokens remain `nil` instead of becoming false.

- [ ] **Step 4: Add failing report interpretation tests**

Assert:

- warp values `[1440.9, 603.1, 498.6, 288.6, 351.7, 377.5, 441.0, 366.4, 278.9, 341.3, 438.3, 299.8, 297.9, 431.4, 358.5, 364.3]` produce median 365.35 ms, min 278.9, max 1,440.9;
- image cache at 382.5/384 is `nearCapacity`, but not memory pressure;
- Working Set at exactly 90 % is near limit and exactly 100 % exceeds it;
- native/Content Patcher nested scopes remain separate and no summed total exists;
- stable gameplay excludes title/load minutes, inactive minutes and every Probe minute whose `(At - WallSeconds, At]` contains `WarpRequest`, complete, abort or excluded timestamp; midnight rollover is covered and uncorrelatable clocks add `.transitionWindowsUnknown`;
- SLO cost reads `MsPerSecond`; `patchesMeasured == false` adds limitation;
- one missing source yields partial report, never zero;
- a single run adds `.singleSession` and `.noControlRun`.

- [ ] **Step 5: Run interpretation tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticReportTests`

Expected: parser tests pass; new aggregation assertions fail.

- [ ] **Step 6: Implement report builder**

Keep raw evidence and display classification separate. Parse the last `[OPTIMIZER CONFIG]` in the sliced log via a new `parseLatest`/reverse traversal; regression fixture includes a migration line and two config lines. Use last valid cumulative snapshot per marker family and median over finite completed warps. Reuse `ProbeLoadBreakdown.of` for load totals and per-mod direct costs. Pick `primaryWait` only within matching launch evidence, with source label; never compare launch and save scopes, call it cause or sum overlapping scopes. SLO steady cost comes only from matching `neoiw.StardewLoadingOptimizer` rows that also pass stable-minute filters. Derive absolute SLO timestamps from session date, including midnight rollover, before excluding every warp request/completion/abort/exclusion window.

- [ ] **Step 7: Run focused tests and verify GREEN**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticReportTests`

Expected: all report tests pass.

- [ ] **Step 8: Commit**

```bash
git add Package.swift StarHubTH/Models/SloDiagnosticLog.swift StarHubTH/Models/SloDiagnosticReport.swift StarHubTH/Models/SloOptimizerConfig.swift Tests/SloDiagnosticTests/SloDiagnosticReportTests.swift Tests/SmapiLogParserTests/SloOptimizerConfigTests.swift
git commit -m "feat(performance): analyze SLO diagnostic sessions"
```

---

### Task 4: Corrélation stricte du journal et de la sonde

**Files:**
- Create: `StarHubTH/Models/SloDiagnosticSources.swift`
- Create: `Tests/SloDiagnosticTests/SloDiagnosticSourcesTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: bookmark/snapshot Task 2, report input Task 3, `ProbeFiles.sessions()`, `.inventory()`, `.loads()`.
- Produces:
  - `SloDiagnosticSourceReader.bookmark(logURL:) -> SloDiagnosticLogBookmark?`
  - `SloDiagnosticSourceReader.newLog(current: Data?, bookmark: SloDiagnosticLogBookmark?, modified: Date?, launchRequestedAt: Date) -> String?`
  - `SloDiagnosticCorrelation.select(snapshot:sessions:inventory:loads:) -> SloDiagnosticCorrelationResult`
  - `SloDiagnosticConfigMatch` cases `.exact`, `.normalizationCandidate(sha256: String)`
  - `SloDiagnosticProbeCandidate { input, selectedSessionId, configMatch }`
  - `SloDiagnosticCorrelationResult { candidate, ambiguousNewSessions, unreadableLines }`

- [ ] **Step 1: Add failing log-boundary tests**

Cases:

1. current bytes preserve old prefix and append new lines — return suffix only;
2. current file is smaller/replaced, differs from bookmark and modified no earlier than five seconds before `launchRequestedAt` — return whole current log;
3. unchanged bytes/hash — return nil;
4. replaced file older than preparation — return nil;
5. old prefix differs despite larger size — treat as replacement, not suffix.

- [ ] **Step 2: Run boundary tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticSourcesTests`

Expected: compile failure because source reader is absent.

- [ ] **Step 3: Implement bookmark and log slicing**

Bookmark existing file size, SHA-256 and mtime. For append, hash current prefix of bookmarked size. For replacement, require changed bytes and mtime within the fixed five-second tolerance around launch request. Read files through injected URLs; no default path in tests.

- [ ] **Step 4: Add failing probe-correlation tests**

Build synthetic sessions around `launchRequestedAt`. Assert known session IDs excluded, pre-launch sessions excluded, inventory without `mrbabilo.StarHubFR.Probe` rejected, exact SLO SHA match selected, SLO SHA mismatch returned as a normalization candidate rather than silently accepted, only selected session loads/costs/minutes retained, and multiple candidates report ambiguity. A session without matching inventory remains partial rather than borrowing previous inventory.

- [ ] **Step 5: Run correlation tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticSourcesTests`

Expected: boundary tests pass; correlation tests fail.

- [ ] **Step 6: Implement correlation**

Require new session ID absent from snapshot and inventory date >= `launchRequestedAt` with clock tolerance fixed at five seconds. Inventory must contain `mrbabilo.StarHubFR.Probe` plus `neoiw.StardewLoadingOptimizer`. Rank exact diagnostic SHA first; surface a different nonnil SLO SHA as `.normalizationCandidate`, never as accepted evidence. Select a session only after Task 5 validates that candidate against on-disk bytes, true Boolean diagnostic keys and latest effective SLO config line. Filter every probe source by exact session string. Multiple candidates remain ambiguous; never borrow an older inventory.

- [ ] **Step 7: Run focused tests and verify GREEN**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticSourcesTests`

Expected: all source tests pass.

- [ ] **Step 8: Commit**

```bash
git add Package.swift StarHubTH/Models/SloDiagnosticSources.swift Tests/SloDiagnosticTests/SloDiagnosticSourcesTests.swift
git commit -m "feat(performance): correlate SLO diagnostic evidence"
```

---

### Task 5: Store de session, restauration et reprise

**Files:**
- Create: `StarHubTH/Models/SloDiagnosticExclusion.swift`
- Create: `StarHubTH/Stores/SloDiagnosticSessionStore.swift`
- Create: `Tests/SloDiagnosticStoreTests/SloDiagnosticSessionStoreTests.swift`
- Modify: `StarHubTH/Stores/BenchmarkRunner.swift`
- Modify: `StarHubTH/BisectionRunner.swift`
- Modify: `StarHubTH/Stores/ProbePerformanceStore.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `@MainActor struct SloDiagnosticRuntime` closures `isGameRunning`, `busyReason`, `launchProfile`, `modEnabled(rootFolderName:) -> Bool?`, `setModEnabled(rootFolderName:enabled:) async -> Bool`, `grantOwnerWriteAccess(URL)`, `launchGame() -> Bool`, `rescan() async -> Void`, plus injected clock/sleeper for deterministic monitoring tests
  - `SloDiagnosticPreparation { slo: SloDiagnosticInstallation, probeRootFolderName: String, probeWasEnabled: Bool }`
  - `SloDiagnosticReportReceipt { formatVersion = 1, completedAt, sessionId, report, sourceFingerprints }`
  - `SloDiagnosticReportStore.save/load/clear` for derived report receipt only; no raw log/config bytes
  - `SloDiagnosticExclusion` pure decisions plus `SloDiagnosticSnapshotStore.hasPending(in:)` durable check shared by all four flows
  - `@MainActor @Observable final class SloDiagnosticSessionStore`
  - `init(applicationSupport: URL?, logURL: URL, probeFiles: ProbeFiles)`; production passes `AppSupport.directory`, journal par défaut et `ProbeFiles()`
  - `State` cases `.idle`, `.unavailable(SloDiagnosticReadiness)`, `.ready(SloDiagnosticPreparation)`, `.preparing`, `.waitingForGame`, `.running`, `.restoring`, `.report(SloDiagnosticReport)`, `.recoveryBlocked(SloDiagnosticRecoveryConflict)`, `.failed(SloDiagnosticFailure)`
  - `reload(mods:gameDir:runtime:) async`
  - `start(_ preparation: SloDiagnosticPreparation, runtime: SloDiagnosticRuntime) async`
  - `gameExited(runtime:) async`
  - `resumeIfNeeded(mods:gameDir:runtime:) async`
  - `confirmOverwriteAndRestore(runtime:) async`

- [ ] **Step 1: Add failing happy-path lifecycle test**

Inject temporary config/log/probe directories and closure counters. Assert order:

1. snapshot persisted before first mutation;
2. paused SLO and probe roots enabled and verified;
3. config written at active path, reread and SHA verified;
4. launch called once;
5. exit builds and persists derived report;
6. original bytes restored at active path before initial mod states;
7. snapshot cleared only last.

- [ ] **Step 2: Run store test and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticSessionStoreTests`

Expected: compile failure because store/runtime do not exist.

- [ ] **Step 3: Implement preparation and normal completion**

Store only observable state on MainActor. Run config/source reads and report build in `Task.detached`; pass `Data`, URLs and Sendable structs. Revalidate SMAPI profile, disk root state and every precondition after sheet confirmation. Deduplicate mutation roots when SLO and Probe share a group. Persist full snapshot before mutation, enable roots, verify real state because `toggleMod` callback carries no result, then grant owner write access and write active config. Roll back in reverse order: config first, each unique root once. Poll every few seconds: seen then gone waits the same three-second source-settle delay as `GameExit.publisher`, then completes; never seen for 90 s restores as launch failure. Notification and poll call one guarded finalizer, so they cannot build/restore twice.

- [ ] **Step 4: Add failing recovery/concurrency tests**

Cover game active, Vanilla profile, game closed, divergent config, missing config, paused/grouped paths, read-only directory repair, toggle callback without state change, exact config SHA, valid SLO normalization, invalid/user-changed normalization candidate, crash before `launchRequestedAt`, partial preparation/rollback states, launch failure, never-seen timeout, seen-then-gone with three-second settle, simultaneous exit notification/poll, restart at 30 s/91 s, unavailable Mods volume, missing root, active/paused collision, unreadable snapshot, two `resumeIfNeeded` calls, stale reload generation, report-store write failure, report reload after restart, and another exclusive operation. Assert no blind overwrite, config restore precedes root disable, and no duplicate launch/restoration.

- [ ] **Step 5: Run recovery tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticSessionStoreTests`

Expected: happy path passes; recovery and stale-generation cases fail.

- [ ] **Step 6: Implement recovery and idempotence**

Use snapshot as durable authority. Persist `launchRequestedAt` before launching and `gameSeen` on first observation. Before any recovery, require resolved Mods root plus exactly one expected physical root per changed mod; offline volume, missing roots or `X`/`.X` collision publish `.recoveryBlocked`. For each root, temporary state is restored, initial state is idempotently accepted, anything else conflicts. Resolve config path from current root state: active path while temporary, initial path once root is already restored. When inventory reports a changed SLO SHA, add it atomically to accepted hashes only if current bytes have that SHA, both diagnostic keys are real Boolean `true`, and sliced log’s latest config confirms diagnostics; otherwise keep it conflicting. On resume, nil `launchRequestedAt` rolls back preparation immediately; running game keeps plan; unseen game inside 90 s restarts monitoring; seen-and-closed or unseen after timeout analyzes available evidence then restores. If current config equals an accepted hash, restore automatically; if already original, continue root restoration; otherwise publish `.recoveryBlocked`. Save derived report before clearing snapshot, but restore even if receipt save fails. A task generation and one finalization token guard every async publication. `confirmOverwriteAndRestore` is only path allowed to replace divergent content.

Add bidirectional exclusion tests: pending SLO snapshot blocks `BenchmarkRunner.busyReason`, `BisectionRunner.start` and `ProbePerformanceStore.prepare`; active/interrupted benchmark, active bisection and guided plan block SLO preparation. Use injected snapshot directory/closure in tests rather than real Application Support.

- [ ] **Step 7: Run focused tests and verify GREEN**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticSessionStoreTests`

Expected: all store tests pass.

- [ ] **Step 8: Commit**

```bash
git add Package.swift StarHubTH/Models/SloDiagnosticExclusion.swift StarHubTH/Stores/SloDiagnosticSessionStore.swift StarHubTH/Stores/BenchmarkRunner.swift StarHubTH/BisectionRunner.swift StarHubTH/Stores/ProbePerformanceStore.swift Tests/SloDiagnosticStoreTests/SloDiagnosticSessionStoreTests.swift
git commit -m "feat(performance): orchestrate reversible SLO diagnostics"
```

---

### Task 6: Interface Performances, installation Nexus et documentation

**Files:**
- Create: `StarHubTH/Models/SloDiagnosticPresentation.swift`
- Create: `StarHubTH/Views/Performance/PerformanceSloDiagnosticSection.swift`
- Modify: `StarHubTH/StarHubTHViewModel.swift` (adaptateur attente UniqueID Nexus, aucun état)
- Modify: `StarHubTH/Views/DiagnosticsView.swift`
- Modify: `StarHubTH/Views/Performance/PerformanceView.swift`
- Modify: `StarHubTH/L10n.swift`
- Modify: `assets/en.json`
- Modify: `assets/fr.json`
- Modify: `Package.swift`
- Modify: `CHANGELOG.md`
- Modify: `docs/ROADMAP.md`
- Test: `Tests/SloDiagnosticStoreTests/SloDiagnosticPresentationTests.swift`

**Interfaces:**
- Consumes: Task 5 store/state, `expectAndDownloadNexusMod(nexusId:uniqueId:)` et `expectNexusMod(nexusId:uniqueId:)` (petits adaptateurs vers `MissingDependencyStore.recordExpectation`, sans état VM neuf), `nexusDirectDownloadUnavailable`, `downloadingNexusModId`, `pendingNexusSource`, `pendingDownloadedZip`, `pendingExpectedDependencyIds`, `MissingDependencies.filesPage`, `ProbeBundle`, `toggleMod(_:completion:)`, `launchGame(honoringCloseAfterLaunch:)`, `GameExit.publisher`, `UDKey.launchProfile`.
- Produces: visible card and confirmation sheet; runtime adapter in `DiagnosticsView`/view helper; no ViewModel field.

- [ ] **Step 1: Add failing presentation-decision tests**

Keep view-free decision helper in same store/model test target. Assert button/title/action states for absent direct-download, absent webpage, paused, ready, incompatible, downloading, downloaded archive awaiting installation, Probe missing/outdated/unavailable/newer, Vanilla profile, game running, pending recovery and completed report. Critical assertion: transition absent → found after scan offers preparation and emits no launch action. Installation SLO records expected UniqueID for both direct and webpage/NXM paths; archive mismatch is rejected by existing install preview.

- [ ] **Step 2: Run presentation tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticPresentationTests`

Expected: compile failure because presentation decision type is absent.

- [ ] **Step 3: Implement card and sheet**

Place `PerformanceSloDiagnosticSection` immediately after summary card with `.id("slo")`, and add it after Summary in adaptive section navigation. Use `AdaptiveLabels` for install/open/prepare/retry; use existing Nexus download, page and ProbeBundle install routes. While archive 50153 awaits its install sheet, show that state and suppress duplicate action. Sheet lists exact temporary changes, including sibling mods activated by a grouped root, and restoration. Report shows verdict/date, four concise rows, visible limitations and disclosure details. Render precomputed marks with Swift Charts: nonstacked load bars, warp points/median, separate frame/memory timelines, plus cache capacity bars. Require at least two marks for a chart; otherwise show text. Reuse `ChartHover` and reserve a fixed one-line detail slot exactly like `PerformanceSmoothnessSection`, so hover/click never changes card height. Add VoiceOver labels, keyboard selector and explicit units. Recovery conflict offers dossier and explicit confirmed restore actions. No UI-side statistics.

- [ ] **Step 4: Integrate ownership and lifecycle**

Own store as `@State` in `DiagnosticsView`, pass to `PerformanceView`, construct runtime from current ViewModel gestures without adding stored VM state. On task/segment/app activation call `reload` or `resumeIfNeeded`; on `GameExit.publisher` call `gameExited`, then reload existing performance/environment stores. Guard hidden tab rendering as current view does.

- [ ] **Step 5: Add bilingual copy and package sources**

Add one `L10n.PerformanceSloDiagnostic` namespace. Keep FR/EN key parity. Text must say « attente observée », « cache utilisé », « mesure unique » and « données insuffisantes »; never « SLO a causé » or « temps économisé » without control run.

- [ ] **Step 6: Update user-visible docs**

Add `[Unreleased]` CHANGELOG entry. Mark D2-T4 delivered in ROADMAP with automatic install proposal, temporary two-key config, crash recovery and parsed report. Add D2-T4’s SLO config keys, Nexus ID and session-correlation use to existing `docs/SOURCES.md` SLO entry; do not invent a new source or update source baseline merely to silence drift. Preserve D4-T9 validation evidence already present in working tree.

- [ ] **Step 7: Run focused and localization tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnostic
python3 -m json.tool assets/en.json >/dev/null
python3 -m json.tool assets/fr.json >/dev/null
```

Expected: SLO diagnostic tests pass; both JSON files valid.

- [ ] **Step 8: Commit**

```bash
git add Package.swift StarHubTH/Models/SloDiagnosticPresentation.swift StarHubTH/StarHubTHViewModel.swift StarHubTH/Views/DiagnosticsView.swift StarHubTH/Views/Performance/PerformanceView.swift StarHubTH/Views/Performance/PerformanceSloDiagnosticSection.swift StarHubTH/L10n.swift assets/en.json assets/fr.json CHANGELOG.md docs/ROADMAP.md docs/SOURCES.md Tests/SloDiagnosticStoreTests/SloDiagnosticPresentationTests.swift
git commit -m "feat(performance): add guided SLO diagnostic session"
```

---

## Final verification

- [ ] Run `python3 build_app.py`; require exit 0, Swift 6 compile, localization parity and standards gate.
- [ ] Run `./run_tests.sh`; require complete suite with zero failure.
- [ ] Run `python3 check_standards.py --report`; record counters and confirm no increase.
- [ ] Run `python3 check_sources.py --offline`; explain any SLO contract drift, never update baseline merely to silence it.
- [ ] Inspect `git diff --check`, `git status --short` and commit range; leave `Tests/ContentPatcherPacksTests/ZZRealParcProbe.swift`, `Tests/ProbeFilesTests/ProbeOptionsTests.swift` and `Tests/SaveFingerprintTests/ZZProbe.swift` untouched.
- [ ] Perform one whole-branch code review; fix Critical/Important once through RED→GREEN, ledger Minor findings.
- [ ] Human GUI verification: SLO absent → installation proposal; paused → temporary activation; launch/quit → report and restoration; app restart mid-session; navigation; hover without line jump; keyboard/VoiceOver labels; 560 pt; Réduire les animations.

## Completion contract

- SLO missing never creates transaction; installation follows existing Nexus behavior and never auto-launches.
- Every disk mutation has persisted recovery information first.
- Paused/grouped roots use persisted initial and active paths; config is restored before roots are repointed.
- Automatic restoration happens only from exact expected temporary state.
- Report uses exactly one post-launch session whose inventory contains Probe and SLO; config SHA is exact or an explicitly attested normalization, and missing evidence is named.
- No nested SLO scopes are added together and no single run is stated as causal proof.
- Full build/tests pass; roadmap and changelog describe shipped behavior.
