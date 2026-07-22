# Automated Tests for ModConfigBackupManager (Pilot) — Design

## Goal

Stand up automated-test infrastructure for StarHubTH — a project with zero
existing tests — starting with a single pilot manager, `ModConfigBackupManager`,
chosen because it's small, self-contained, and the manager where the most
subtle bugs (nested-pack-folder path flattening, missing index locking,
folder-name collisions) were found and fixed during the July 2026 audit.
If the pilot proves the approach works smoothly, the same pattern extends to
`SaveManager`, `ModInstallBackupManager`, and `ModZipInstaller` in later,
separate specs.

## Why this is needed

The audit that fixed 49 findings this session found its Critical bugs almost
entirely in file-manipulation managers (backup/restore/install paths).
Without tests, every future change to these managers risks silently
reintroducing the same class of bug (a race, a swallowed error, a
mis-reconstructed path) with no automated signal before a user hits it.

## Constraints discovered during exploration

- The project has **no Xcode project** and **no XCTest target** — it builds
  via `build_app.py`, which globs `StarHubTH/*.swift` and invokes `swiftc`
  directly.
- `xcodebuild`/`swift test` require `XCTest`/`Testing`, which are not visible
  under the active `xcode-select` developer directory (Command Line Tools
  only) on this machine — but Xcode.app *is* installed
  (`/Applications/Xcode.app`, Xcode 26.6). Setting `DEVELOPER_DIR` to
  `/Applications/Xcode.app/Contents/Developer` **for the single test command**
  (no global `xcode-select -s`, no sudo, no system-wide change) makes
  `swift test` work correctly. Verified empirically with a throwaway SPM
  package.
- `ModItem`/`ModDependency` (needed by `ModConfigBackupManager`) are defined
  inline inside `StarHubTHViewModel.swift` (2600+ lines, coupled to
  SwiftUI/Combine via `ObservableObject`/`@Published`). They are themselves
  plain Foundation structs with no SwiftUI dependency.
- `ModConfigBackupManager` is a singleton (`static let shared`) whose `init()`
  hardcodes `~/Library/Application Support/StarHubTH/Backups/ModConfigs` as
  its backups directory — tests must not write there.

## Global Constraints

- No change to `build_app.py`'s build output or behavior.
- No change to `ModConfigBackupManager`'s production behavior — the only
  production-code change is an additive, default-preserving constructor
  parameter.
- Tests must never touch the real
  `~/Library/Application Support/StarHubTH/Backups/ModConfigs` directory.
- Test framework: **Swift Testing** (`import Testing`, `@Test`, `#expect`) —
  matches what `swift package init` generates by default on this toolchain
  (Swift 6.3) and is Apple's current direction.
- `.build/` is already covered by `.gitignore` — no changes needed there.

---

## Architecture

A single `Package.swift` at the repository root, alongside `build_app.py`.
The two build paths are fully independent: `build_app.py` still globs and
compiles `StarHubTH/*.swift` directly into `StarHubTH.app` exactly as before;
`swift test` builds a separate SPM library target that happens to reuse a
few of the same source files (via SPM's explicit per-file `sources:` list,
not a copy) plus one modified file.

```text
StarHubTH/                          (existing app source folder, unchanged
                                      layout — build_app.py keeps globbing
                                      all *.swift files here)
├── ModItem.swift                   (NEW — extracted from
                                      StarHubTHViewModel.swift)
├── ModConfigBackup.swift           (existing, unchanged)
├── L10n.swift                      (existing, unchanged)
├── ModConfigBackupManager.swift    (existing — init() signature changes,
                                      see below)
├── StarHubTHViewModel.swift        (existing — loses the ModItem/
                                      ModDependency struct bodies, gains
                                      nothing else)
└── ... (all other app files, untouched, not part of the library target)

Package.swift                       (NEW — repo root)
Tests/
└── ModConfigBackupManagerTests/
    └── ModConfigBackupManagerTests.swift   (NEW)
run_tests.sh                        (NEW — sets DEVELOPER_DIR, runs `swift test`)
```

### Package.swift

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StarHubTHCore",
    platforms: [.macOS(.v14)], // matches Info.plist's LSMinimumSystemVersion
    products: [
        .library(name: "StarHubTHCore", targets: ["StarHubTHCore"]),
    ],
    targets: [
        .target(
            name: "StarHubTHCore",
            path: "StarHubTH",
            sources: [
                "ModItem.swift",
                "ModConfigBackup.swift",
                "L10n.swift",
                "ModConfigBackupManager.swift",
            ]
        ),
        .testTarget(
            name: "ModConfigBackupManagerTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModConfigBackupManagerTests"
        ),
    ]
)
```

`sources:` cherry-picks exactly those 4 files out of `StarHubTH/` — every
other file in that folder (views, the rest of the ViewModel, other managers)
is invisible to this target and to `build_app.py`'s own build is unaffected
since it never looks at `Package.swift`.

### `StarHubTH/ModItem.swift` (new file)

Contains exactly the `ModDependency` and `ModItem` struct definitions,
moved verbatim out of `StarHubTHViewModel.swift`. No behavior change.

### `ModConfigBackupManager.swift` — the one production change

```swift
private let fm = FileManager.default
private let backupsBasePath: URL
private let backupsDirPath: URL
private let metadataPath: URL
private let indexLock = NSLock()

// ...

/// `backupsBasePath` is exposed only for tests to point this manager at an
/// isolated temporary directory instead of the real Application Support
/// folder. Production code always uses `.shared`, which calls this with
/// `nil` and gets the exact same directory as before.
init(backupsBasePath overrideBasePath: URL? = nil) {
    let base = overrideBasePath ?? (
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    ).appendingPathComponent("StarHubTH/Backups/ModConfigs", isDirectory: true)
    backupsBasePath = base
    backupsDirPath = base.appendingPathComponent("backups", isDirectory: true)
    metadataPath = base.appendingPathComponent("metadata.json")
    try? fm.createDirectory(at: backupsDirPath, withIntermediateDirectories: true)
}

static let shared = ModConfigBackupManager()
```

The existing `private init()` becomes `init(backupsBasePath:)`, no longer
`private` — the test target is a separate SPM module, so anything it
constructs or calls directly must be `public`.

### Visibility changes needed (SPM module boundary only)

`build_app.py` compiles every file as one module via `swiftc`, so access
modifiers are inert for the app build — this section only matters for the
separate library target the tests link against:

- `ModConfigBackupManager`: the class itself, `init(backupsBasePath:)`,
  `static let shared`, `createBackup`, `restoreBackup`, `deleteBackup`,
  `cleanupOldBackups`, `loadBackups`, and `BackupError` (the enum and its
  cases) → `public`.
- `ModConfigBackup`, `ModConfigBackupItem`, `ModConfigBackupsIndex`
  (in `ModConfigBackup.swift`) → `public` types with **explicit `public
  init(...)`** — Swift's auto-generated memberwise initializer for a
  struct is only as visible as the struct's *default* (internal) access
  level even when the struct itself is marked `public`, so each needs a
  hand-written public initializer or tests can't construct/compare them.
- `ModItem`, `ModDependency` (in the new `ModItem.swift`) → same treatment:
  `public` struct + explicit `public init(...)`, since tests construct
  fake `ModItem` values directly in memory (see Data flow, step 2).
- `L10n.Saves.*` constants used by `ModConfigBackupManager`'s dependents →
  no change needed; `L10n` and its nested enums/`static let` constants are
  already effectively public-safe as plain string constants, but the
  `L10n` enum and the specific case(s) referenced must still be marked
  `public` for the library target to compile against them.

## Data flow (test execution)

1. Each `@Test` function creates a fresh `ModConfigBackupManager(backupsBasePath: tempDir)` where `tempDir` is a unique subdirectory under
   `FileManager.default.temporaryDirectory`, created in the test and removed
   in a `defer` (or Swift Testing's equivalent teardown) regardless of pass/fail.
2. Tests also create a throwaway fake "game directory" (another temp
   subdirectory) with a `Mods/` folder populated with fake mod folders
   (containing `manifest.json`-shaped `ModItem` values passed directly —
   `ModItem` is constructed in-memory, no need to write real manifest.json
   files) and `config.json`/`fr.json` fixtures as needed per test.
3. Assertions use `#expect(...)` against the returned `ModConfigBackup`
   values, the on-disk file tree (via `FileManager`), and thrown errors
   (via `#expect(throws:)`).

## Test list (pilot coverage)

1. `createBackup` — standalone enabled mod with `config.json` → backup
   created, index has 1 entry, file content matches source.
2. `createBackup` — group pack with an enabled child → child's file backed
   up under the group's nested path (regression test for the flattening bug
   fixed this session).
3. `createBackup` — standalone mod nested in a subfolder without being
   tagged `isGroup` (single-manifest "pack" case) → nested path preserved,
   not flattened (the other half of the same regression).
4. `createBackup` — no enabled mods → throws `.noEnabledMods`.
5. `createBackup` — enabled mods present but none have `config.json`/`fr.json`
   → throws `.nothingToBackUp`, and the empty backup folder is removed (not
   left on disk, not listed by `loadBackups()`).
6. `restoreBackup` — selected item's files are copied into `Mods/`,
   overwriting the current (different) content.
7. `restoreBackup` — creates a best-effort pre-restore backup of the current
   state before overwriting.
8. `deleteBackup` — removes both the on-disk folder and the index entry.
9. `cleanupOldBackups` — keeps the 5 most recent regardless of age; deletes
   only those both non-recent (beyond the 5) and older than 30 days.
10. Two backups created back-to-back get distinct folder names (UUID
    suffix prevents same-second collisions).
11. `loadBackups()` returns entries sorted most-recent-first.

## Running the tests

```sh
./run_tests.sh
```

`run_tests.sh`:

```sh
#!/usr/bin/env bash
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
```

If a contributor's machine doesn't have Xcode.app installed (Command Line
Tools only), this script will fail with a clear `xcrun` error pointing at
the missing path — acceptable for a first pilot; revisited if this becomes
a real barrier for other contributors.

## Out of scope for this spec

- `SaveManager`, `ModInstallBackupManager`, `ModZipInstaller` tests (future,
  separate specs once this pilot is validated).
- CI integration (no CI currently exists in this repo).
- UI/View testing.
