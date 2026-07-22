# ModConfigBackupManager Test Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up automated-test infrastructure for StarHubTH (a project with zero existing tests) and write a full regression-test suite for `ModConfigBackupManager`, proving the pattern before it's extended to the other file-manipulation managers.

**Architecture:** A `Package.swift` at the repo root defines an SPM library target (`StarHubTHCore`) that cherry-picks 3 existing source files out of `StarHubTH/` (via an explicit `sources:` list, no duplication) plus one new file, and a Swift Testing test target that depends on it. `build_app.py`'s own build (globbing and `swiftc`-compiling all of `StarHubTH/*.swift` into the `.app`) is completely untouched by this — the two build paths coexist independently.

**Tech Stack:** Swift 6.3 toolchain, Swift Package Manager, Swift Testing (`import Testing`).

## Global Constraints

- No change to `build_app.py`'s build output or behavior.
- No change to `ModConfigBackupManager`'s **production** behavior — `static let shared` must resolve to the exact same directory as before (`~/Library/Application Support/StarHubTH/Backups/ModConfigs`).
- Tests must never touch the real `~/Library/Application Support/StarHubTH/Backups/ModConfigs` directory — every test uses its own temp directory, injected via the manager's new `backupsBasePath` initializer parameter.
- Test framework: Swift Testing (`import Testing`, `@Test`, `#expect`), per the approved spec.
- Running tests requires `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (Command Line Tools alone lack `Testing`/`XCTest`) — wrapped in `run_tests.sh` so this never needs to be typed by hand.
- `.build/` is already covered by `.gitignore` — no changes needed there.

---

### Task 1: Extract `ModItem`/`ModDependency` into their own file

**Files:**
- Create: `StarHubTH/ModItem.swift`
- Modify: `StarHubTH/StarHubTHViewModel.swift:16-44`

**Interfaces:**
- Produces: `public struct ModDependency` and `public struct ModItem`, both with an explicit `public init(...)` whose parameter names/order/defaults exactly match the original implicit memberwise initializer — so every existing call site elsewhere in `StarHubTHViewModel.swift` (which constructs `ModItem` via keyword arguments) keeps compiling unchanged.

- [ ] **Step 1: Create `StarHubTH/ModItem.swift`**

```swift
import Foundation

public struct ModDependency: Equatable {
    public let uniqueId: String
    public let isRequired: Bool

    public init(uniqueId: String, isRequired: Bool) {
        self.uniqueId = uniqueId
        self.isRequired = isRequired
    }
}

public struct ModItem: Identifiable, Equatable {
    public var id: String { folderName }
    public let uniqueId: String
    public let name: String
    public let folderName: String
    public let version: String
    public let author: String
    public let description: String
    public let nexusUrl: String
    /// Numeric Nexus Mods mod id parsed from `UpdateKeys: ["nexus:191"]` in the
    /// mod manifest. Empty when the mod doesn't declare a Nexus update key.
    public let nexusModId: String
    public var isEnabled: Bool
    public let dependencies: [ModDependency]
    public var children: [ModItem]?
    public var isGroup: Bool = false
    /// Content-modification date of the mod's `manifest.json` on disk, captured
    /// at scan time. Used to detect same-version updates: when the installed
    /// version equals the Nexus latest but the Nexus upload is newer than this
    /// file, the installed copy is stale and an update is offered. `nil` for
    /// group headers and when the date can't be read.
    public var installedFileDate: Date? = nil

    public init(
        uniqueId: String,
        name: String,
        folderName: String,
        version: String,
        author: String,
        description: String,
        nexusUrl: String,
        nexusModId: String,
        isEnabled: Bool,
        dependencies: [ModDependency],
        children: [ModItem]? = nil,
        isGroup: Bool = false,
        installedFileDate: Date? = nil
    ) {
        self.uniqueId = uniqueId
        self.name = name
        self.folderName = folderName
        self.version = version
        self.author = author
        self.description = description
        self.nexusUrl = nexusUrl
        self.nexusModId = nexusModId
        self.isEnabled = isEnabled
        self.dependencies = dependencies
        self.children = children
        self.isGroup = isGroup
        self.installedFileDate = installedFileDate
    }
}
```

- [ ] **Step 2: Remove the same two structs from `StarHubTHViewModel.swift`**

Delete lines 16-44 (the blank line after the closing brace of `ModItem` is deleted too, so exactly one blank line remains between the `Dictionary` extension and `ModUpdateInfo`). Before:

```swift
struct ModDependency: Equatable {
    let uniqueId: String
    let isRequired: Bool
}

struct ModItem: Identifiable, Equatable {
    var id: String { folderName }
    let uniqueId: String
    let name: String
    let folderName: String
    let version: String
    let author: String
    let description: String
    let nexusUrl: String
    /// Numeric Nexus Mods mod id parsed from `UpdateKeys: ["nexus:191"]` in the
    /// mod manifest. Empty when the mod doesn't declare a Nexus update key.
    let nexusModId: String
    var isEnabled: Bool
    let dependencies: [ModDependency]
    var children: [ModItem]?
    var isGroup: Bool = false
    /// Content-modification date of the mod's `manifest.json` on disk, captured
    /// at scan time. Used to detect same-version updates: when the installed
    /// version equals the Nexus latest but the Nexus upload is newer than this
    /// file, the installed copy is stale and an update is offered. `nil` for
    /// group headers and when the date can't be read.
    var installedFileDate: Date? = nil
}

struct ModUpdateInfo: Identifiable, Equatable {
```

After:

```swift
struct ModUpdateInfo: Identifiable, Equatable {
```

(everything above and below this span in the file is untouched)

- [ ] **Step 3: Verify the main app still builds**

Run: `python3 build_app.py`
Expected: last line `[SUCCESS] Successfully built StarHubTH.app` — this proves every existing `ModItem(...)` construction site in the app (there are many, in `scanMods()` and elsewhere) still compiles against the new explicit initializer.

- [ ] **Step 4: Commit**

```bash
git add StarHubTH/ModItem.swift StarHubTH/StarHubTHViewModel.swift
git commit -m "refactor: extract ModItem/ModDependency into their own file

Both are plain Foundation structs with no SwiftUI/Combine dependency;
pulling them out of StarHubTHViewModel.swift lets a future test target
depend on them without pulling in the whole 2600-line ViewModel."
```

---

### Task 2: Stand up the SPM library + test target, with one smoke test

**Files:**
- Modify: `StarHubTH/ModConfigBackup.swift` (add `public` to types, add explicit `public init` to `ModConfigBackupItem`)
- Modify: `StarHubTH/ModConfigBackupManager.swift` (add `public` to the class, `BackupError`, and its public methods; replace `private init()` with `public init(backupsBasePath:)`)
- Create: `Package.swift`
- Create: `Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift`
- Create: `run_tests.sh`

**Interfaces:**
- Produces: `ModConfigBackupManager(backupsBasePath: URL? = nil)` (public init — `nil` preserves the exact production directory), and the test-file helpers `makeTestMod(...)`, `writeTestFile(in:filename:content:)`, and `struct TestEnvironment` (properties: `manager: ModConfigBackupManager`, `gameDir: String`, `modsDir: URL`; method `cleanup()`) — every later task's tests use these exact names/signatures.

- [ ] **Step 1: Make `ModConfigBackup.swift`'s types public**

Modify `StarHubTH/ModConfigBackup.swift`. Change:

```swift
struct ModConfigBackupItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let modFolderName: String
    let parentFolderName: String?
    let modDisplayName: String
    let files: [String]
    let fileSizes: [String: Int]
}
```

to:

```swift
public struct ModConfigBackupItem: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public let modFolderName: String
    public let parentFolderName: String?
    public let modDisplayName: String
    public let files: [String]
    public let fileSizes: [String: Int]

    public init(modFolderName: String, parentFolderName: String?, modDisplayName: String, files: [String], fileSizes: [String: Int]) {
        self.modFolderName = modFolderName
        self.parentFolderName = parentFolderName
        self.modDisplayName = modDisplayName
        self.files = files
        self.fileSizes = fileSizes
    }
}
```

Change:

```swift
struct ModConfigBackup: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let timestamp: Date
    let items: [ModConfigBackupItem]
    let totalFiles: Int
    let totalSize: Int
```

to:

```swift
public struct ModConfigBackup: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public let timestamp: Date
    public let items: [ModConfigBackupItem]
    public let totalFiles: Int
    public let totalSize: Int
```

Change the existing custom initializer from:

```swift
    init(id: UUID = UUID(), timestamp: Date, items: [ModConfigBackupItem], totalFiles: Int, totalSize: Int, folderName: String) {
```

to:

```swift
    public init(id: UUID = UUID(), timestamp: Date, items: [ModConfigBackupItem], totalFiles: Int, totalSize: Int, folderName: String) {
```

And the `folderName` stored property declaration from `var folderName: String` to `public var folderName: String`. Leave `ModConfigBackupsIndex` and `CodingKeys`/`init(from:)`/`encode(to:)` exactly as they are — `ModConfigBackupsIndex` never appears in the manager's public API surface, so it doesn't need to be public, and the `Codable` machinery doesn't need touching.

Also make the two computed properties public — change:

```swift
    var formattedDate: String {
```

to `public var formattedDate: String {`, and:

```swift
    var formattedSize: String {
```

to `public var formattedSize: String {`.

- [ ] **Step 2: Make `ModConfigBackupManager.swift` public, with the injectable init**

Modify `StarHubTH/ModConfigBackupManager.swift`. Change:

```swift
class ModConfigBackupManager {
    static let shared = ModConfigBackupManager()

    enum BackupError: LocalizedError {
        case gameDirEmpty
        case noEnabledMods
        /// Every enabled mod was scanned but none had a config.json/fr.json
        /// to back up — distinct from `.noEnabledMods` (no mods to even
        /// consider).
        case nothingToBackUp

        var errorDescription: String? {
            switch self {
            case .gameDirEmpty: return "Game directory is not set."
            case .noEnabledMods: return "No enabled mods to back up."
            case .nothingToBackUp: return "None of the enabled mods have config files to back up."
            }
        }
    }
```

to:

```swift
public class ModConfigBackupManager {
    public static let shared = ModConfigBackupManager()

    public enum BackupError: LocalizedError {
        case gameDirEmpty
        case noEnabledMods
        /// Every enabled mod was scanned but none had a config.json/fr.json
        /// to back up — distinct from `.noEnabledMods` (no mods to even
        /// consider).
        case nothingToBackUp

        public var errorDescription: String? {
            switch self {
            case .gameDirEmpty: return "Game directory is not set."
            case .noEnabledMods: return "No enabled mods to back up."
            case .nothingToBackUp: return "None of the enabled mods have config files to back up."
            }
        }
    }
```

Change the initializer from:

```swift
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        backupsBasePath = appSupport.appendingPathComponent("StarHubTH/Backups/ModConfigs", isDirectory: true)
        backupsDirPath = backupsBasePath.appendingPathComponent("backups", isDirectory: true)
        metadataPath = backupsBasePath.appendingPathComponent("metadata.json")
        try? fm.createDirectory(at: backupsDirPath, withIntermediateDirectories: true)
    }
```

to:

```swift
    /// `backupsBasePath` is exposed only so tests can point this manager at
    /// an isolated temporary directory instead of the real Application
    /// Support folder. Production code always uses `.shared`, which calls
    /// this with `nil` and gets the exact same directory as before.
    public init(backupsBasePath overrideBasePath: URL? = nil) {
        let base = overrideBasePath ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StarHubTH/Backups/ModConfigs", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("StarHubTH/Backups/ModConfigs", isDirectory: true)
        backupsBasePath = base
        backupsDirPath = base.appendingPathComponent("backups", isDirectory: true)
        metadataPath = base.appendingPathComponent("metadata.json")
        try? fm.createDirectory(at: backupsDirPath, withIntermediateDirectories: true)
    }
```

Add `public` to every method the tests will call. Change each of these signatures (bodies unchanged):

- `func loadBackups() -> [ModConfigBackup] {` → `public func loadBackups() -> [ModConfigBackup] {`
- `func createBackup(gameDir: String, mods: [ModItem]) throws -> ModConfigBackup {` → `public func createBackup(gameDir: String, mods: [ModItem]) throws -> ModConfigBackup {`
- `func restoreBackup(gameDir: String, backup: ModConfigBackup, selectedItems: [ModConfigBackupItem], currentMods: [ModItem]) throws {` → `public func restoreBackup(gameDir: String, backup: ModConfigBackup, selectedItems: [ModConfigBackupItem], currentMods: [ModItem]) throws {`
- `func deleteBackup(_ backup: ModConfigBackup) throws {` → `public func deleteBackup(_ backup: ModConfigBackup) throws {`
- `func cleanupOldBackups() -> Int {` → `public func cleanupOldBackups() -> Int {`

Everything else in the file (`private let fm`, `private let indexLock`, `withIndexLock`, `loadIndex`, `saveIndex`, `leafMods`, `destinationDir`, `findConfigFiles`, `makeBackupFolderName`, `backupDirURL`, `deleteBackupFiles`) stays `private`, unchanged.

- [ ] **Step 3: Verify the main app still builds with the visibility changes**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app` — `public` is inert for `build_app.py`'s single-module `swiftc` build, so this should be a no-op verification, but it's the cheapest possible check that nothing was mistyped.

- [ ] **Step 4: Create `Package.swift`**

`ModConfigBackupManager.swift` does not reference `L10n.*` (its error
messages are hardcoded English strings, not L10n keys — confirmed via
`grep -n "L10n\." StarHubTH/ModConfigBackupManager.swift`, no matches), so
`L10n.swift` is not needed in `sources:`. If a future change to
`ModConfigBackupManager.swift` starts referencing `L10n.*`, add
`L10n.swift` to this list and mark the specific referenced enum/constants
`public`, following the same pattern as Step 1/2 above.

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

- [ ] **Step 5: Create the test file with shared helpers and one smoke test**

Create `Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift`:

```swift
import Foundation
import Testing
@testable import StarHubTHCore

// MARK: - Test helpers

/// Builds a `ModItem` for tests with sensible defaults — only the fields a
/// given test cares about need to be passed explicitly.
func makeTestMod(
    uniqueId: String = "test.mod",
    name: String = "Test Mod",
    folderName: String,
    isEnabled: Bool = true,
    children: [ModItem]? = nil,
    isGroup: Bool = false
) -> ModItem {
    ModItem(
        uniqueId: uniqueId,
        name: name,
        folderName: folderName,
        version: "1.0.0",
        author: "Test Author",
        description: "",
        nexusUrl: "",
        nexusModId: "",
        isEnabled: isEnabled,
        dependencies: [],
        children: children,
        isGroup: isGroup,
        installedFileDate: nil
    )
}

/// Writes a UTF-8 text file at `dir/filename`, creating `dir` if needed.
func writeTestFile(in dir: URL, filename: String, content: String = "{}") throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try content.data(using: .utf8)!.write(to: dir.appendingPathComponent(filename))
}

/// One isolated test environment: a fresh temp root containing its own
/// `Backups/` (for the manager) and `Game/Mods/` (the fake game
/// directory), plus a manager instance pointed at that `Backups/` folder.
/// `cleanup()` must be called (via `defer`) at the end of every test.
struct TestEnvironment {
    let manager: ModConfigBackupManager
    let gameDir: String
    let modsDir: URL
    private let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarHubTHTests-\(UUID().uuidString)", isDirectory: true)
        let backupsBase = root.appendingPathComponent("Backups", isDirectory: true)
        let gameDirURL = root.appendingPathComponent("Game", isDirectory: true)
        modsDir = gameDirURL.appendingPathComponent("Mods", isDirectory: true)
        try? FileManager.default.createDirectory(at: modsDir, withIntermediateDirectories: true)
        manager = ModConfigBackupManager(backupsBasePath: backupsBase)
        gameDir = gameDirURL.path
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

// MARK: - Tests

@Suite struct ModConfigBackupManagerTests {

    @Test func freshEnvironmentHasNoBackups() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        #expect(env.manager.loadBackups().isEmpty)
    }
}
```

- [ ] **Step 6: Create `run_tests.sh`**

```sh
#!/usr/bin/env bash
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
```

Run: `chmod +x run_tests.sh`

- [ ] **Step 7: Run the smoke test**

Run: `./run_tests.sh`
Expected: output ending with something like:

```
✔ Test run with 1 test in 1 suite passed after 0.00X seconds.
```

If it fails to build with a visibility error (`'x' is inaccessible due to 'internal' protection level`), re-check Steps 1-2 for a missed `public`.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Tests/ run_tests.sh StarHubTH/ModConfigBackup.swift StarHubTH/ModConfigBackupManager.swift
git commit -m "test: stand up SPM test target for ModConfigBackupManager

Adds a Package.swift + Swift Testing target alongside build_app.py's
existing swiftc-based build (the two are fully independent). Makes
ModConfigBackupManager and its model types public so the test target
(a separate module) can construct and call them, and adds an injectable
backupsBasePath so tests never touch the real Application Support
directory. One smoke test proves the whole pipeline compiles and links."
```

---

### Task 3: `createBackup` — standalone mod (success + no-enabled-mods error)

**Files:**
- Modify: `Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `makeTestMod`, `writeTestFile` (Task 2).

- [ ] **Step 1: Add the two tests**

Add inside `@Suite struct ModConfigBackupManagerTests { ... }`, after `freshEnvironmentHasNoBackups`:

```swift
    @Test func createBackupBacksUpStandaloneModConfigFile() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let modDir = env.modsDir.appendingPathComponent("StandaloneMod", isDirectory: true)
        try writeTestFile(in: modDir, filename: "config.json", content: "{\"volume\": 5}")

        let mod = makeTestMod(folderName: "StandaloneMod")
        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod])

        #expect(backup.items.count == 1)
        #expect(backup.items[0].modFolderName == "StandaloneMod")
        #expect(backup.items[0].files == ["config.json"])
        #expect(backup.totalFiles == 1)
        #expect(env.manager.loadBackups().count == 1)
    }

    @Test func createBackupThrowsWhenNoModsAreEnabled() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let mod = makeTestMod(folderName: "DisabledMod", isEnabled: false)

        do {
            _ = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod])
            Issue.record("Expected createBackup to throw .noEnabledMods")
        } catch ModConfigBackupManager.BackupError.noEnabledMods {
            // expected
        } catch {
            Issue.record("Expected .noEnabledMods, got \(error)")
        }
    }
```

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `Test run with 3 tests in 1 suite passed`.

- [ ] **Step 3: Commit**

```bash
git add Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift
git commit -m "test: cover createBackup for a standalone mod (success + no-enabled-mods)"
```

---

### Task 4: `createBackup` — group pack & nested-pack path regression

**Files:**
- Modify: `Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `makeTestMod`, `writeTestFile` (Task 2).

These two tests are regression tests for the July 2026 bug where a mod's
nested `Mods/`-relative folder path got flattened to just its last path
component during backup/restore, resolving to a phantom top-level folder
instead of the real nested location.

- [ ] **Step 1: Add the two tests**

```swift
    @Test func createBackupPreservesGroupChildNestedPath() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let childDir = env.modsDir.appendingPathComponent("GroupFolder/ChildFolder", isDirectory: true)
        try writeTestFile(in: childDir, filename: "config.json")

        let child = makeTestMod(uniqueId: "child", folderName: "GroupFolder/ChildFolder")
        let group = makeTestMod(uniqueId: "group", folderName: "GroupFolder", children: [child], isGroup: true)

        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [group])

        #expect(backup.items.count == 1)
        #expect(backup.items[0].modFolderName == "GroupFolder/ChildFolder")
        #expect(backup.items[0].parentFolderName == "GroupFolder")
    }

    @Test func createBackupPreservesStandaloneNestedPackPath() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let modDir = env.modsDir.appendingPathComponent("PackFolder/ModX", isDirectory: true)
        try writeTestFile(in: modDir, filename: "config.json")

        // Not tagged isGroup — mirrors scanFolderForMods only setting
        // isGroup when a folder contains 2+ manifests; a single mod nested
        // one level deep still carries its full relative path in
        // `folderName`.
        let mod = makeTestMod(folderName: "PackFolder/ModX")

        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod])

        #expect(backup.items.count == 1)
        #expect(backup.items[0].modFolderName == "PackFolder/ModX")
        #expect(backup.items[0].parentFolderName == nil)
    }
```

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `Test run with 5 tests in 1 suite passed`.

- [ ] **Step 3: Commit**

```bash
git add Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift
git commit -m "test: regression-cover the nested-pack-folder path flattening bug"
```

---

### Task 5: `createBackup` — nothing-to-back-up error

**Files:**
- Modify: `Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `makeTestMod`, `writeTestFile` (Task 2).

- [ ] **Step 1: Add the test**

```swift
    @Test func createBackupThrowsWhenNoConfigFilesFound() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        // Mod folder exists and is enabled, but has no config.json/fr.json.
        let modDir = env.modsDir.appendingPathComponent("NoConfigMod", isDirectory: true)
        try writeTestFile(in: modDir, filename: "manifest.json", content: "{}")

        let mod = makeTestMod(folderName: "NoConfigMod")

        do {
            _ = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod])
            Issue.record("Expected createBackup to throw .nothingToBackUp")
        } catch ModConfigBackupManager.BackupError.nothingToBackUp {
            // expected
        } catch {
            Issue.record("Expected .nothingToBackUp, got \(error)")
        }

        #expect(env.manager.loadBackups().isEmpty)
    }
```

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `Test run with 6 tests in 1 suite passed`.

- [ ] **Step 3: Commit**

```bash
git add Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift
git commit -m "test: cover createBackup's nothingToBackUp error"
```

---

### Task 6: `restoreBackup` — overwrite + pre-restore safety backup

**Files:**
- Modify: `Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `makeTestMod`, `writeTestFile` (Task 2).

- [ ] **Step 1: Add the two tests**

```swift
    @Test func restoreBackupOverwritesLiveConfigFile() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let modDir = env.modsDir.appendingPathComponent("RestoreMod", isDirectory: true)
        try writeTestFile(in: modDir, filename: "config.json", content: "{\"value\": \"original\"}")

        let mod = makeTestMod(folderName: "RestoreMod")
        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod])

        // Simulate the user changing the live config after the backup.
        try writeTestFile(in: modDir, filename: "config.json", content: "{\"value\": \"changed\"}")

        try env.manager.restoreBackup(
            gameDir: env.gameDir,
            backup: backup,
            selectedItems: backup.items,
            currentMods: [mod]
        )

        let restoredContent = try String(contentsOf: modDir.appendingPathComponent("config.json"), encoding: .utf8)
        #expect(restoredContent == "{\"value\": \"original\"}")
    }

    @Test func restoreBackupCreatesSafetyBackupOfCurrentState() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let modDir = env.modsDir.appendingPathComponent("RestoreMod", isDirectory: true)
        try writeTestFile(in: modDir, filename: "config.json", content: "{\"value\": \"original\"}")

        let mod = makeTestMod(folderName: "RestoreMod")
        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod])

        try writeTestFile(in: modDir, filename: "config.json", content: "{\"value\": \"changed\"}")

        try env.manager.restoreBackup(
            gameDir: env.gameDir,
            backup: backup,
            selectedItems: backup.items,
            currentMods: [mod]
        )

        // restoreBackup takes a best-effort backup of the pre-restore state
        // before overwriting — there should now be 2 backups total (the
        // original one created above, plus the automatic safety one).
        #expect(env.manager.loadBackups().count == 2)
    }
```

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `Test run with 8 tests in 1 suite passed`.

- [ ] **Step 3: Commit**

```bash
git add Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift
git commit -m "test: cover restoreBackup's overwrite and pre-restore safety backup"
```

---

### Task 7: `deleteBackup` + folder-name uniqueness

**Files:**
- Modify: `Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `makeTestMod`, `writeTestFile` (Task 2).

- [ ] **Step 1: Add the two tests**

```swift
    @Test func deleteBackupRemovesItFromTheIndex() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let modDir = env.modsDir.appendingPathComponent("DeleteMod", isDirectory: true)
        try writeTestFile(in: modDir, filename: "config.json")

        let mod = makeTestMod(folderName: "DeleteMod")
        let backup = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod])
        #expect(env.manager.loadBackups().count == 1)

        try env.manager.deleteBackup(backup)

        #expect(env.manager.loadBackups().isEmpty)
    }

    @Test func twoBackupsCreatedBackToBackGetDistinctFolderNames() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let modDir = env.modsDir.appendingPathComponent("SameSecondMod", isDirectory: true)
        try writeTestFile(in: modDir, filename: "config.json")

        let mod = makeTestMod(folderName: "SameSecondMod")
        let first = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod])
        let second = try env.manager.createBackup(gameDir: env.gameDir, mods: [mod])

        #expect(first.folderName != second.folderName)
        #expect(env.manager.loadBackups().count == 2)

        // Deleting one must not affect the other — proves they're on
        // distinct on-disk folders, not sharing one that a single delete
        // would wipe.
        try env.manager.deleteBackup(first)
        #expect(env.manager.loadBackups().count == 1)
        #expect(env.manager.loadBackups()[0].id == second.id)
    }
```

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `Test run with 10 tests in 1 suite passed`.

- [ ] **Step 3: Commit**

```bash
git add Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift
git commit -m "test: cover deleteBackup and same-second folder-name uniqueness"
```

---

### Task 8: `cleanupOldBackups` — 5-backup floor + 30-day cutoff

`cleanupOldBackups` computes its 30-day cutoff from the real, current
`Date()` — there's no injectable clock. To test the age-based logic
without waiting 30 real days, this task adds one small **internal**
(not `public`) seeding method to `ModConfigBackupManager`, reachable from
the test target only via `@testable import` — invisible to any real
consumer of the library, inert for `build_app.py`. This is the one place
this plan adds a method beyond the injectable-init change described in the
approved spec; flagged here since it's additional production-file surface,
even though it changes no existing behavior.

**Files:**
- Modify: `StarHubTH/ModConfigBackupManager.swift` (add `seedIndexForTesting`)
- Modify: `Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment` (Task 2).
- Produces: `func seedIndexForTesting(with backups: [ModConfigBackup])` (internal) on `ModConfigBackupManager`.

- [ ] **Step 1: Add the seeding method**

In `StarHubTH/ModConfigBackupManager.swift`, add this method in the `// MARK: - Index` section, right after `saveIndex`:

```swift
    /// Test-only seam (visible via `@testable import`) for seeding the
    /// index with pre-fabricated backups — lets tests exercise
    /// timestamp-dependent logic (like `cleanupOldBackups`'s 30-day cutoff)
    /// without waiting real time or injecting a fake clock. Deliberately
    /// left internal (not `public`) — invisible to any real consumer of
    /// this library.
    func seedIndexForTesting(with backups: [ModConfigBackup]) {
        withIndexLock {
            var index = loadIndex()
            index.backups.append(contentsOf: backups)
            saveIndex(index)
        }
    }
```

- [ ] **Step 2: Add the two tests**

```swift
    @Test func cleanupOldBackupsKeepsFiveMostRecentRegardlessOfAge() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let veryOld = Date().addingTimeInterval(-60 * 24 * 60 * 60) // 60 days ago
        let fabricated = (0..<6).map { i in
            ModConfigBackup(
                timestamp: veryOld.addingTimeInterval(Double(i)),
                items: [], totalFiles: 0, totalSize: 0,
                folderName: "fake-backup-\(i)"
            )
        }
        env.manager.seedIndexForTesting(with: fabricated)
        #expect(env.manager.loadBackups().count == 6)

        let deletedCount = env.manager.cleanupOldBackups()

        // All 6 are >30 days old, but the 5 most recent must survive
        // regardless of age.
        #expect(deletedCount == 1)
        #expect(env.manager.loadBackups().count == 5)
    }

    @Test func cleanupOldBackupsDeletesBackupsBeyondFloorAndCutoff() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let now = Date()
        var fabricated: [ModConfigBackup] = []
        // 5 recent backups (within 30 days) — always protected by the floor.
        for i in 0..<5 {
            fabricated.append(ModConfigBackup(
                timestamp: now.addingTimeInterval(Double(-i)),
                items: [], totalFiles: 0, totalSize: 0,
                folderName: "recent-\(i)"
            ))
        }
        // 3 more, older than 30 days — eligible for deletion since they
        // fall outside both the 5-most-recent floor and the 30-day window.
        let old = now.addingTimeInterval(-45 * 24 * 60 * 60)
        for i in 0..<3 {
            fabricated.append(ModConfigBackup(
                timestamp: old.addingTimeInterval(Double(-i)),
                items: [], totalFiles: 0, totalSize: 0,
                folderName: "old-\(i)"
            ))
        }
        env.manager.seedIndexForTesting(with: fabricated)
        #expect(env.manager.loadBackups().count == 8)

        let deletedCount = env.manager.cleanupOldBackups()

        #expect(deletedCount == 3)
        #expect(env.manager.loadBackups().count == 5)
        #expect(env.manager.loadBackups().allSatisfy { $0.folderName.hasPrefix("recent-") })
    }
```

- [ ] **Step 3: Run the tests**

Run: `./run_tests.sh`
Expected: `Test run with 12 tests in 1 suite passed`.

- [ ] **Step 4: Verify the main app still builds**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app` (the new method is internal Foundation code, inert for the app build, but this task touched production code so re-verify).

- [ ] **Step 5: Commit**

```bash
git add StarHubTH/ModConfigBackupManager.swift Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift
git commit -m "test: cover cleanupOldBackups' 5-backup floor and 30-day cutoff

Adds an internal (not public) seedIndexForTesting seam, reachable only
via @testable import, so timestamp-dependent cleanup logic can be
tested without waiting real time or introducing an injectable clock."
```

---

### Task 9: `loadBackups` sort order

**Files:**
- Modify: `Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `seedIndexForTesting` (Task 8).

- [ ] **Step 1: Add the test**

```swift
    @Test func loadBackupsReturnsNewestFirst() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let now = Date()
        let fabricated = [
            ModConfigBackup(timestamp: now.addingTimeInterval(-100), items: [], totalFiles: 0, totalSize: 0, folderName: "oldest"),
            ModConfigBackup(timestamp: now, items: [], totalFiles: 0, totalSize: 0, folderName: "newest"),
            ModConfigBackup(timestamp: now.addingTimeInterval(-50), items: [], totalFiles: 0, totalSize: 0, folderName: "middle"),
        ]
        env.manager.seedIndexForTesting(with: fabricated)

        let loaded = env.manager.loadBackups()

        #expect(loaded.map(\.folderName) == ["newest", "middle", "oldest"])
    }
```

- [ ] **Step 2: Run the full suite one last time**

Run: `./run_tests.sh`
Expected: `Test run with 13 tests in 1 suite passed`.

- [ ] **Step 3: Final full verification**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app`.

- [ ] **Step 4: Commit**

```bash
git add Tests/ModConfigBackupManagerTests/ModConfigBackupManagerTests.swift
git commit -m "test: cover loadBackups' newest-first sort order

Pilot complete: 13 tests covering ModConfigBackupManager's create,
restore, delete, cleanup, and load paths, including regression
coverage for the nested-pack-folder path flattening bug fixed in the
July 2026 audit."
```
