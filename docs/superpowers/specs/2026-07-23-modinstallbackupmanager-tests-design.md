# Automated Tests for ModInstallBackupManager — Design

## Goal

Extend the test pattern established by the `ModConfigBackupManager` pilot
(see `docs/superpowers/specs/2026-07-22-modconfigbackupmanager-tests-design.md`)
to `ModInstallBackupManager` — the manager that backs up/restores complete
mod folders around install/update/restore operations. This is the second
of the 3 remaining file-manipulation managers the pilot was meant to pave
the way for.

## Why this manager next

Architecturally closest to `ModConfigBackupManager` (same singleton +
locked-JSON-index shape), but with real additional complexity worth
locking down:

- `createBackup` copies a **whole mod folder** (not a per-file scan), from
  either `Mods/` or `Mods_disabled/` depending on `mod.isEnabled`.
- `restoreBackup` contains this session's Critical audit fix: move the
  live folder aside → copy from the backup → **roll back the move if the
  copy fails** → on success, register the replaced folder as its own new
  backup (reading real metadata from its `manifest.json`) rather than
  discarding it. This is the highest-risk logic in the class and the main
  reason to prioritize this manager.
- `cleanupOldBackups` uses a **3-tier retention policy** (5-most-recent
  floor + everything ≤30 days + most-recent-per-calendar-month beyond
  that) — more complex than `ModConfigBackupManager`'s 2-tier version, and
  never covered by a test before.

## What's already in place from the pilot (no rework needed)

- `ModItem` is already extracted and `public` (`StarHubTH/ModItem.swift`) —
  reusable as-is.
- The `Package.swift` / `StarHubTHCore` library target already exists.
- The `DEVELOPER_DIR` + `run_tests.sh` wrapper already exists and needs no
  changes.
- Unlike `ModConfigBackup`, none of `ModInstallBackup`/`ModMetadata`/
  `BackupReason`/`ModInstallBackupsIndex` have a hand-written
  `init(from:)`/`encode(to:)` — they use plain `Codable` synthesis, which
  auto-matches the type's access level. So marking them `public` needs no
  extra explicit-initializer work for `Codable` (unlike the pilot's Task 2
  deviation) — only an explicit `public init(...)` for the normal
  memberwise construction tests need.

## New dependency: `ZipModInfo.swift`

`ModInstallBackupManager.extractMetadata(fromModFolder:)` (used by the
restore-safety-backup path) parses a real `manifest.json` via
`ModManifest(dict:)`, defined in `StarHubTH/ZipModInfo.swift`. That file
only imports `Foundation` and is self-contained, but also defines several
other types (`ValidationStatus`, `ConflictType`, `DetectedMod`, etc.) not
needed here. Splitting `ModManifest` into its own file isn't warranted by
this task (unlike `ModItem`, `ZipModInfo.swift` isn't awkwardly stuck
inside an unrelated large file — it's already a small, focused, portable
file; the "extra" types are inert and harmless to include). Decision: add
the whole file to `sources:` rather than fragment it further.

## Global Constraints

(Same as the pilot, restated for this manager)

- No change to `build_app.py`'s build output or behavior.
- No change to `ModInstallBackupManager`'s **production** behavior —
  `static let shared` must resolve to the exact same directory as before
  (`~/Library/Application Support/StarHubTH/Backups/ModInstalls`).
- Tests must never touch that real directory — every test uses its own
  temp directory, injected via the manager's new `backupsBasePath`
  initializer parameter (same pattern as the pilot).
- Test framework: Swift Testing.
- `.build/` already gitignored.

---

## Architecture

Same `Package.swift`, extended:

```text
StarHubTH/
├── ModInstallBackup.swift          (existing — types made public)
├── ModInstallBackupManager.swift   (existing — init() signature changes,
│                                     same pattern as the pilot)
├── ZipModInfo.swift                (existing, unchanged — added to
│                                     sources: only for ModManifest)
└── ... (everything else, untouched)

Tests/
├── ModConfigBackupManagerTests/    (existing, pilot — untouched)
└── ModInstallBackupManagerTests/   (NEW)
    └── ModInstallBackupManagerTests.swift
```

### `Package.swift` changes

Add to the existing `StarHubTHCore` target's `sources:`:
```swift
"ModInstallBackup.swift",
"ModInstallBackupManager.swift",
"ZipModInfo.swift",
```

Add a new test target:
```swift
.testTarget(
    name: "ModInstallBackupManagerTests",
    dependencies: ["StarHubTHCore"],
    path: "Tests/ModInstallBackupManagerTests"
),
```

### `ModInstallBackupManager.swift` — the one production change

Same shape as the pilot: `private init()` → `public init(backupsBasePath overrideBasePath: URL? = nil)`, preserving the exact production path when called with `nil`. `ModInstallBackupManager` itself, `InstallBackupError` (+ its `errorDescription`), and every method the tests call (`loadBackups`, `createBackup`, `restoreBackup`, `deleteBackup`, `cleanupOldBackups`) become `public`.

### `ModInstallBackup.swift` — visibility only

`BackupReason`, `ModMetadata`, `ModInstallBackup` (+ explicit `public init` for its memberwise construction — tests build fixtures directly), `ModInstallBackupsIndex` stay internal (never appears in the manager's public API, same reasoning as the pilot's `ModConfigBackupsIndex`). `formattedDate` becomes `public`.

### `ZipModInfo.swift` — visibility only

Only `ModManifest` needs `public` (+ explicit `public init`, since a test must construct a real one to write a `manifest.json` fixture the restore-safety path can parse). Everything else in the file stays internal — unused by this test target, harmless.

## Test helpers (new file, same shapes as the pilot for consistency)

- `makeTestMod(...)` — reused as-is from the pattern (can't literally reuse the pilot's *file*, since it's a different test target/module — this target gets its own copy, matching the same signature).
- `writeTestFile(in:filename:content:)` — reused pattern.
- `writeManifest(in dir: URL, uniqueId:name:version:author:)` — NEW: writes a real, valid `manifest.json` fixture (JSON matching the shape `ModManifest(dict:)` parses: `Name`, `UniqueID`, `Version`, `Author` keys) — needed only for the restore-safety-backup tests, since that's the one path that reads a real manifest off disk instead of taking metadata from a `ModItem`.
- `TestEnvironment` — same shape as the pilot (`manager`, `gameDir`, `modsDir`, `cleanup()`), plus a `modsDisabledDir: URL` computed property (`gameDir`'s `Mods_disabled` folder) since this manager's restore path targets that folder specifically.

## Test list

1. `createBackup` — enabled mod (source read from `Mods/`) → backup created, file content matches, index has 1 entry.
2. `createBackup` — disabled mod (source read from `Mods_disabled/`) → same, proving the `mod.isEnabled` branch.
3. `createBackup` — mod folder doesn't exist on disk → throws `.modNotFound`.
4. `createBackup` — empty `gameDir` → throws `.gameDirEmpty`.
5. `restoreBackup` — no existing live folder at the destination → straight copy succeeds, file content matches the backup.
6. `restoreBackup` — an existing live folder at the destination → gets replaced, restored content matches the backup, AND the replaced folder is registered as its own new backup with `reason == .beforeRestore` and metadata read from its real `manifest.json` (uses `writeManifest`).
7. `restoreBackup` — **rollback on copy failure**: pre-create the destination's parent (`Mods_disabled`) read-only (`chmod 0o555`) so the internal `copyItem` call fails after the live folder was already moved aside; assert `restoreBackup` throws `.restoreFailed`, AND that the original live folder's content is back in place afterward (proving the rollback ran), AND restore permissions before test cleanup.
8. `restoreBackup` — backup's `backupPath` doesn't exist on disk → throws `.restoreFailed` cleanly, without touching any live folder.
9. `deleteBackup` — removes both the on-disk folder and the index entry.
10. Two backups created back-to-back get distinct folder names (UUID suffix, same pattern as the pilot).
11. `cleanupOldBackups` — 5-backup floor holds regardless of age (mirrors the pilot's equivalent test).
12. `cleanupOldBackups` — the 30-day window keeps everything within it, beyond the floor.
13. `cleanupOldBackups` — **the 3rd tier**: beyond 30 days, only the most-recent-per-calendar-month survives (fabricate backups in 3 distinct months, all older than 30 days, expect exactly 1 survivor per month plus the floor).
14. `loadBackups` — sorted newest-first.

Test 7 and test 13 are the two genuinely new, higher-value additions this
manager's extra complexity calls for — everything else mirrors the pilot's
already-proven pattern.

## Out of scope for this spec

- `SaveManager` and `ModZipInstaller` tests (future, separate specs).
- Fixing the two Minor gaps the pilot's final review deferred as
  fast-follows (those belong to `ModConfigBackupManager`, not this
  manager).
