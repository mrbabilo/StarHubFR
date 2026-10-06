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
3. SLO normalise/modifie `config.json` pendant jeu : restauration automatique refuse écrasement — Task 2, test `changedDiagnosticFileRequiresResolution`.
4. Notification de fermeture manquée ou StarHubFR redémarré : plan présent et jeu fermé déclenche reprise idempotente — Task 5, tests `resumeRestoresClosedSession` et `secondResumeDoesNothing`.
5. Installation Nexus terminée pendant carte ouverte : état se recalcule depuis scan et ne lance jamais jeu — Task 6, test de présentation `installedSloOffersPreparationWithoutAutoLaunch`.

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
  - `SloDiagnosticInstallation { rootFolderName, rootPhysicalFolderName, componentRelativePath, version, isEnabled, configURL }`
  - `SloDiagnosticDiscovery` cases `.absent`, `.found(SloDiagnosticInstallation)`, `.ambiguous([String])`
  - `SloDiagnosticCompatibility` cases `.compatible`, `.outdated(String)`, `.missingConfig`, `.invalidConfig`
  - `SloDiagnosticReadiness` cases `.sloAbsent`, `.sloDownloading`, `.sloPaused(SloDiagnosticInstallation)`, `.ready(SloDiagnosticInstallation)`, `.incompatible(String)`, `.ambiguous([String])`, `.probeMissing`, `.probePaused`, `.blocked(String)`
  - `SloDiagnosticInstallRoute` cases `.directDownload(Int)`, `.webPage(URL)`
  - `SloDiagnosticContract.discover(mods:gameDir:) -> SloDiagnosticDiscovery`
  - `SloDiagnosticContract.compatibility(installation:configData:) -> SloDiagnosticCompatibility`
  - `SloDiagnosticContract.readiness(discovery:compatibility:probe:downloading:busyReason:) -> SloDiagnosticReadiness`
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
#expect(found.configURL.path == "/Game/Mods/.Pack/SLO/config.json")
#expect(SloDiagnosticContract.installRoute(directDownloadUnavailable: false) == .directDownload(50153))
#expect(SloDiagnosticContract.installRoute(directDownloadUnavailable: true) ==
        .webPage(MissingDependencies.filesPage(nexusId: 50153)))
```

Add duplicate UniqueID case and version boundary `0.9.9`/`1.0.0`.

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
  - `SloDiagnosticSnapshot: Codable, Equatable, Sendable` with UUID, `startedAt`, installation folders/states, original config, diagnostic SHA-256, log bookmark and known probe session IDs
  - `SloDiagnosticPreparedConfig { data: Data, original: SloDiagnosticConfigState, sha256: String }`
  - `SloDiagnosticRestoreDecision` cases `.restore(Data)`, `.remove`, `.alreadyRestored`, `.conflict`
  - `SloDiagnosticTransaction.prepare(original: Data?, version: String) throws -> SloDiagnosticPreparedConfig`
  - `SloDiagnosticTransaction.restoreDecision(snapshot:current:) -> SloDiagnosticRestoreDecision`
  - `SloDiagnosticSnapshotStore.save/load/clear(..., in directory: URL?)`

- [ ] **Step 1: Add failing config preparation tests**

Tests cover strict scalar refusal, JSON5 comments/trailing comma, unknown nested values, absent file on SLO 1.0.0, old version refusal, invalid existing key type, and exact two booleans enabled. Decode output and assert unknown values remain semantically equal; do not assert formatting.

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

- [ ] **Step 5: Run restoration tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticTransactionTests`

Expected: new restoration tests fail until decisions/store exist.

- [ ] **Step 6: Implement restoration decision and snapshot store**

Compare current bytes to diagnostic SHA and exact original bytes. Never restore when current content matches neither. Store snapshot with `.atomic`; clear only after successful filesystem and mod-state restoration.

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
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `SloOptimizerConfig`, `ProbeSession`, `ProbeLoadRecord`, `ProbeLoadBreakdown`, `ProbeModCostMinute`.
- Produces:
  - `SloDiagnosticLog.parse(_:) -> SloDiagnosticLog`
  - typed cache/image/prefetch/deferred/SpaceCore/native/hotspot/warp/slow-update records
  - `SloDiagnosticProbeInput { session: ProbeSession?, loads: [ProbeLoadRecord], inventory: ProbeInventoryLaunch? }`
  - `enum SloDiagnosticLimitation: String, Codable, Equatable, Sendable`
  - `SloDiagnosticReport.build(log:probe:startedAt:) -> SloDiagnosticReport`
  - report fields `config`, `launch`, `save`, `primaryWait`, `mapCache`, `imageCache`, `prefetch`, `deferredTiles`, `spaceCore`, `warps`, `steadyGameplay`, `sloRuntime`, `memory`, `readyStalls`, `limitations`

- [ ] **Step 1: Add failing marker parser tests**

Use short anonymous strings modeled on 1.0.0 lines. Cover:

- `[MAP CACHE SNAPSHOT]` with 802 hits/0 misses/0 corruptions;
- `[IMAGE CACHE SNAPSHOT]` with 382.5/384 MB, 1,692 hits, 1,604 misses and 179 evictions;
- complete and incomplete prefetch;
- deferred tile and SpaceCore snapshots;
- 16 completed warps, one abort and one excluded transition;
- decimal dot/comma, reordered fields, missing optional field and malformed line.

- [ ] **Step 2: Run parser tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticReportTests`

Expected: compile failure because log/report types do not exist.

- [ ] **Step 3: Implement marker-specific parser**

Parse only known bracket markers. Do not use one comma splitter for every line: nested `top=` lists and localized decimals require marker-specific regular expressions/helpers. Reject non-finite and negative physical counters. Unknown/new lines are ignored and later represented by missing fields.

- [ ] **Step 4: Add failing report interpretation tests**

Assert:

- 16 warp completions produce median 365.35 ms, min 278.9, max 1,440.9;
- image cache at 382.5/384 is `nearCapacity`, but not memory pressure;
- Working Set at exactly 90 % is near limit and exactly 100 % exceeds it;
- native/Content Patcher nested scopes remain separate and no summed total exists;
- stable gameplay excludes title/load minutes, inactive minutes and transition window;
- SLO cost reads `MsPerSecond`; `patchesMeasured == false` adds limitation;
- one missing source yields partial report, never zero;
- a single run adds `.singleSession` and `.noControlRun`.

- [ ] **Step 5: Run interpretation tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticReportTests`

Expected: parser tests pass; new aggregation assertions fail.

- [ ] **Step 6: Implement report builder**

Keep raw evidence and display classification separate. Use median over finite completed warps. Reuse `ProbeLoadBreakdown.of` for load totals and per-mod direct costs. Pick `primaryWait` from largest observed scope with source label; never call it cause and never sum overlapping scopes. SLO steady cost comes only from matching `neoiw.StardewLoadingOptimizer` rows.

- [ ] **Step 7: Run focused tests and verify GREEN**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticReportTests`

Expected: all report tests pass.

- [ ] **Step 8: Commit**

```bash
git add Package.swift StarHubTH/Models/SloDiagnosticLog.swift StarHubTH/Models/SloDiagnosticReport.swift Tests/SloDiagnosticTests/SloDiagnosticReportTests.swift
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
  - `SloDiagnosticSourceReader.newLog(current: Data?, bookmark: SloDiagnosticLogBookmark?, modified: Date?, startedAt: Date) -> String?`
  - `SloDiagnosticCorrelation.select(snapshot:sessions:inventory:loads:) -> SloDiagnosticProbeInput`
  - `SloDiagnosticCorrelationResult { input, selectedSessionId, ambiguousNewSessions, unreadableLines }`

- [ ] **Step 1: Add failing log-boundary tests**

Cases:

1. current bytes preserve old prefix and append new lines — return suffix only;
2. current file is smaller/replaced and modified after `startedAt` — return whole current log;
3. unchanged bytes/hash — return nil;
4. replaced file older than preparation — return nil;
5. old prefix differs despite larger size — treat as replacement, not suffix.

- [ ] **Step 2: Run boundary tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticSourcesTests`

Expected: compile failure because source reader is absent.

- [ ] **Step 3: Implement bookmark and log slicing**

Bookmark existing file size, SHA-256 and mtime. For append, hash current prefix of bookmarked size. For replacement, require mtime postérieure à préparation. Read files through injected URLs; no default path in tests.

- [ ] **Step 4: Add failing probe-correlation tests**

Build synthetic sessions around `startedAt`. Assert known session IDs excluded, pre-start sessions excluded, earliest qualifying new inventory selected, only its loads/costs/minutes retained, and multiple qualifying sessions report ambiguity. A session without matching inventory remains partial rather than borrowing previous inventory.

- [ ] **Step 5: Run correlation tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticSourcesTests`

Expected: boundary tests pass; correlation tests fail.

- [ ] **Step 6: Implement correlation**

Require new session ID absent from snapshot and parsed date >= `startedAt` with small clock tolerance fixed at five seconds. Select first qualifying launch; flag later candidates. Filter every probe source by exact session string.

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
- Create: `StarHubTH/Stores/SloDiagnosticSessionStore.swift`
- Create: `Tests/SloDiagnosticStoreTests/SloDiagnosticSessionStoreTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `@MainActor struct SloDiagnosticRuntime` closures `isGameRunning`, `busyReason`, `modEnabled(rootFolderName:) -> Bool?`, `setModEnabled(rootFolderName:enabled:) async -> Bool`, `launchGame() -> Bool`, `rescan() async -> Void`
  - `SloDiagnosticPreparation { slo: SloDiagnosticInstallation, probeRootFolderName: String, probeWasEnabled: Bool }`
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
2. config written;
3. paused SLO and probe enabled;
4. launch called once;
5. exit builds report;
6. original bytes and initial mod states restored;
7. snapshot cleared only last.

- [ ] **Step 2: Run store test and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticSessionStoreTests`

Expected: compile failure because store/runtime do not exist.

- [ ] **Step 3: Implement preparation and normal completion**

Store only observable state on MainActor. Run config/source reads and report build in `Task.detached`; pass `Data`, URLs and Sendable structs. Roll back completed steps in reverse order if write, enable or launch fails. Poll/reconcile running state on app activation; `GameExit.publisher` remains primary signal.

- [ ] **Step 4: Add failing recovery/concurrency tests**

Cover game active, game closed, divergent config, missing config, toggle failure, launch failure, unreadable snapshot, two `resumeIfNeeded` calls, stale reload generation, and another exclusive operation. Assert no blind overwrite and no duplicate launch/restoration.

- [ ] **Step 5: Run recovery tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticSessionStoreTests`

Expected: happy path passes; recovery and stale-generation cases fail.

- [ ] **Step 6: Implement recovery and idempotence**

Use snapshot as durable authority. If game closed and current config equals diagnostic hash, restore automatically. If divergent, publish `.recoveryBlocked`. A task generation guards every async publication. `confirmOverwriteAndRestore` is only path allowed to replace divergent content.

- [ ] **Step 7: Run focused tests and verify GREEN**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticSessionStoreTests`

Expected: all store tests pass.

- [ ] **Step 8: Commit**

```bash
git add Package.swift StarHubTH/Stores/SloDiagnosticSessionStore.swift Tests/SloDiagnosticStoreTests/SloDiagnosticSessionStoreTests.swift
git commit -m "feat(performance): orchestrate reversible SLO diagnostics"
```

---

### Task 6: Interface Performances, installation Nexus et documentation

**Files:**
- Create: `StarHubTH/Models/SloDiagnosticPresentation.swift`
- Create: `StarHubTH/Views/Performance/PerformanceSloDiagnosticSection.swift`
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
- Consumes: Task 5 store/state, `downloadModFromNexus(nexusId:)`, `nexusDirectDownloadUnavailable`, `downloadingNexusModId`, `MissingDependencies.filesPage`, `toggleMod(_:completion:)`, `launchGame(honoringCloseAfterLaunch:)`, `GameExit.publisher`.
- Produces: visible card and confirmation sheet; runtime adapter in `DiagnosticsView`/view helper; no ViewModel field.

- [ ] **Step 1: Add failing presentation-decision tests**

Keep view-free decision helper in same store/model test target. Assert button/title/action states for absent direct-download, absent webpage, paused, ready, incompatible, downloading, game running, pending recovery and completed report. Critical assertion: transition absent → found after scan offers preparation and emits no launch action.

- [ ] **Step 2: Run presentation tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SloDiagnosticPresentationTests`

Expected: compile failure because presentation decision type is absent.

- [ ] **Step 3: Implement card and sheet**

Place `PerformanceSloDiagnosticSection` immediately after summary card. Use `AdaptiveLabels` for install/open/prepare/retry; use existing Nexus download and page routes. Sheet lists exact temporary changes and restoration. Report shows verdict/date, four concise rows, visible limitations and disclosure details. Recovery conflict offers dossier and explicit confirmed restore actions. No UI-side statistics.

- [ ] **Step 4: Integrate ownership and lifecycle**

Own store as `@State` in `DiagnosticsView`, pass to `PerformanceView`, construct runtime from current ViewModel gestures without adding stored VM state. On task/segment/app activation call `reload` or `resumeIfNeeded`; on `GameExit.publisher` call `gameExited`, then reload existing performance/environment stores. Guard hidden tab rendering as current view does.

- [ ] **Step 5: Add bilingual copy and package sources**

Add one `L10n.PerformanceSloDiagnostic` namespace. Keep FR/EN key parity. Text must say « attente observée », « cache utilisé », « mesure unique » and « données insuffisantes »; never « SLO a causé » or « temps économisé » without control run.

- [ ] **Step 6: Update user-visible docs**

Add `[Unreleased]` CHANGELOG entry. Mark D2-T4 delivered in ROADMAP with automatic install proposal, temporary two-key config, crash recovery and parsed report. Preserve D4-T9 validation evidence already present in working tree.

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
git add Package.swift StarHubTH/Models/SloDiagnosticPresentation.swift StarHubTH/Views/DiagnosticsView.swift StarHubTH/Views/Performance/PerformanceView.swift StarHubTH/Views/Performance/PerformanceSloDiagnosticSection.swift StarHubTH/L10n.swift assets/en.json assets/fr.json CHANGELOG.md docs/ROADMAP.md Tests/SloDiagnosticStoreTests/SloDiagnosticPresentationTests.swift
git commit -m "feat(performance): add guided SLO diagnostic session"
```

---

## Final verification

- [ ] Run `python3 build_app.py`; require exit 0, Swift 6 compile, localization parity and standards gate.
- [ ] Run `./run_tests.sh`; require complete suite with zero failure.
- [ ] Run `python3 check_standards.py --report`; record counters and confirm no increase.
- [ ] Run `python3 check_sources.py --offline`; explain any SLO contract drift, never update baseline merely to silence it.
- [ ] Inspect `git diff --check`, `git status --short` and commit range; leave `Tests/ContentPatcherPacksTests/ZZRealParcProbe.swift`, `Tests/ProbeFilesTests/ProbeOptionsTests.swift` and `Tests/SaveFingerprintTests/ZZProbe.swift` untouched.
- [ ] Dispatch one whole-branch review through `superpowers:requesting-code-review`; fix Critical/Important once through RED→GREEN, ledger Minor findings.
- [ ] Human GUI verification: SLO absent → installation proposal; paused → temporary activation; launch/quit → report and restoration; app restart mid-session; 560 pt; Réduire les animations.

## Completion contract

- SLO missing never creates transaction; installation follows existing Nexus behavior and never auto-launches.
- Every disk mutation has persisted recovery information first.
- Automatic restoration happens only from exact expected temporary state.
- Report uses exactly one post-preparation session and names missing evidence.
- No nested SLO scopes are added together and no single run is stated as causal proof.
- Full build/tests pass; roadmap and changelog describe shipped behavior.
