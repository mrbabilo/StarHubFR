# ModInstallBackupManager Test Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the automated-test pattern established by the `ModConfigBackupManager` pilot to `ModInstallBackupManager`, with real regression coverage for this session's Critical restore-rollback fix and the 3-tier `cleanupOldBackups` retention policy.

**Architecture:** Reuses the pilot's existing `Package.swift`/`StarHubTHCore` library target (add 4 more files to its `sources:`) and adds a new, separate Swift Testing test target `ModInstallBackupManagerTests`. `build_app.py` is untouched.

**Tech Stack:** Swift 6.3 toolchain, Swift Package Manager, Swift Testing.

## Global Constraints

- No change to `build_app.py`'s build output or behavior.
- No change to `ModInstallBackupManager`'s **production** behavior — `static let shared` must resolve to the exact same directory as before (`~/Library/Application Support/StarHubTH/Backups/ModInstalls`).
- Tests must never touch that real directory — every test uses its own temp directory, injected via the manager's new `backupsBasePath` initializer parameter.
- Test framework: Swift Testing (`import Testing`, `@Test`, `#expect`).
- Running tests: `./run_tests.sh` (already exists from the pilot, unchanged).
- `.build/` already covered by `.gitignore`.

**Correction to the approved spec, discovered during planning:** the spec's "New dependency: ZipModInfo.swift" section assumed `ModManifest` would need to be marked `public`. On closer reading, `ModManifest` is only ever used inside `ModInstallBackupManager`'s two **private** helper methods (`extractMetadata`, `registerSetAsideFolderAsBackup`) — it never appears in any public signature. Since the test target only needs to call the manager's own public API, `ModManifest` and everything else in `ZipModInfo.swift` stay fully `internal` (default) — only their *presence in the same compiled module* matters, not their access level. Task 2 below reflects this: zero visibility changes to `ZipModInfo.swift`.

**Second correction:** `ZipModInfo.swift`'s `ModManifest.init?(dict:)` calls `Dictionary.caseInsensitiveValue(forKey:)`, a `Dictionary where Key == String` extension currently defined at the top of `StarHubTHViewModel.swift` (not mentioned in the spec). This must also be pulled out into its own file for the library target to compile — Task 1 below does this, mirroring the pilot's Task 1 (`ModItem` extraction) exactly.

---

### Task 1: Extract `Dictionary.caseInsensitiveValue` into its own file

**Files:**
- Create: `StarHubTH/DictionaryExtensions.swift`
- Modify: `StarHubTH/StarHubTHViewModel.swift:5-15`

**Interfaces:**
- Produces: `Dictionary where Key == String { func caseInsensitiveValue(forKey:) -> Value? }`, identical signature/behavior to the original — every existing call site (`ModManifest.init?(dict:)` in `ZipModInfo.swift`, and any others) keeps compiling unchanged since this is a pure relocation, not a rewrite.

- [ ] **Step 1: Create `StarHubTH/DictionaryExtensions.swift`**

```swift
import Foundation

extension Dictionary where Key == String {
    func caseInsensitiveValue(forKey key: String) -> Value? {
        if let value = self[key] { return value }
        let lowerKey = key.lowercased()
        if let match = self.first(where: { $0.key.lowercased() == lowerKey }) {
            return match.value
        }
        return nil
    }
}
```

- [ ] **Step 2: Remove the same extension from `StarHubTHViewModel.swift`**

Before:

```swift
import Foundation
import Cocoa
import SwiftUI

extension Dictionary where Key == String {
    func caseInsensitiveValue(forKey key: String) -> Value? {
        if let value = self[key] { return value }
        let lowerKey = key.lowercased()
        if let match = self.first(where: { $0.key.lowercased() == lowerKey }) {
            return match.value
        }
        return nil
    }
}

struct ModUpdateInfo: Identifiable, Equatable {
```

After:

```swift
import Foundation
import Cocoa
import SwiftUI

struct ModUpdateInfo: Identifiable, Equatable {
```

(everything else in the file is untouched)

- [ ] **Step 3: Verify the main app still builds**

Run: `python3 build_app.py`
Expected: last line `[SUCCESS] Successfully built StarHubTH.app`.

- [ ] **Step 4: Commit**

```bash
git add StarHubTH/DictionaryExtensions.swift StarHubTH/StarHubTHViewModel.swift
git commit -m "refactor: extract Dictionary.caseInsensitiveValue into its own file

Pure Foundation, no dependencies — needed by ZipModInfo.swift's
ModManifest, which the upcoming ModInstallBackupManager test target
must include (for the internal manifest.json-parsing path)."
```

---

### Task 2: Add the new production files to the SPM target, visibility changes, new test target + smoke test

**Files:**
- Modify: `Package.swift`
- Modify: `StarHubTH/ModInstallBackup.swift` (visibility)
- Modify: `StarHubTH/ModInstallBackupManager.swift` (visibility + injectable init)
- Create: `Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift`

**Interfaces:**
- Produces: `ModInstallBackupManager(backupsBasePath: URL? = nil)` (public init — `nil` preserves the exact production directory), and the test-file helpers `makeTestMod(...)`, `writeTestFile(in:filename:content:)`, `writeManifest(in:uniqueId:name:version:author:)`, `makeFakeBackup(timestamp:folderName:)`, and `struct TestEnvironment` (properties: `manager`, `gameDir: String`, `modsDir: URL`, `modsDisabledDir: URL`; method `cleanup()`) — every later task's tests use these exact names/signatures.
- Consumes: `ModItem` (from Task 1 of the pilot, already public).

- [ ] **Step 1: Make `ModInstallBackup.swift`'s types public**

Modify `StarHubTH/ModInstallBackup.swift`. Change:

```swift
/// Reason for creating a mod install backup
enum BackupReason: String, Codable {
    case beforeInstall
    case beforeUpdate
    /// The live version set aside just before a backup was restored over
    /// it — registered as its own backup (rather than discarded) so
    /// restoring is itself undoable.
    case beforeRestore
}

/// Metadata about a mod extracted from manifest.json
struct ModMetadata: Codable, Equatable {
    let name: String
    let version: String
    let author: String
    let uniqueId: String
}

/// Backup of a complete mod folder before installation or update.
/// Stored in ~/Library/Application Support/StarHubTH/Backups/ModInstalls/
struct ModInstallBackup: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let timestamp: Date
    let originalFolderName: String
    let backupPath: String
    let modMetadata: ModMetadata
    let reason: BackupReason
    
    var formattedDate: String {
```

to:

```swift
/// Reason for creating a mod install backup
public enum BackupReason: String, Codable {
    case beforeInstall
    case beforeUpdate
    /// The live version set aside just before a backup was restored over
    /// it — registered as its own backup (rather than discarded) so
    /// restoring is itself undoable.
    case beforeRestore
}

/// Metadata about a mod extracted from manifest.json
public struct ModMetadata: Codable, Equatable {
    public let name: String
    public let version: String
    public let author: String
    public let uniqueId: String

    public init(name: String, version: String, author: String, uniqueId: String) {
        self.name = name
        self.version = version
        self.author = author
        self.uniqueId = uniqueId
    }
}

/// Backup of a complete mod folder before installation or update.
/// Stored in ~/Library/Application Support/StarHubTH/Backups/ModInstalls/
public struct ModInstallBackup: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public let timestamp: Date
    public let originalFolderName: String
    public let backupPath: String
    public let modMetadata: ModMetadata
    public let reason: BackupReason

    public init(id: UUID = UUID(), timestamp: Date, originalFolderName: String, backupPath: String, modMetadata: ModMetadata, reason: BackupReason) {
        self.id = id
        self.timestamp = timestamp
        self.originalFolderName = originalFolderName
        self.backupPath = backupPath
        self.modMetadata = modMetadata
        self.reason = reason
    }

    public var formattedDate: String {
```

Note: `BackupReason` needs no explicit `Equatable`/custom init — Swift automatically supports `==` on raw-value enums with no associated values even without declaring `: Equatable` (verified empirically: `enum X: String, Codable { case a, b }; X.a == .a` compiles and returns `true`). `ModInstallBackupsIndex` (the remaining type in this file) stays untouched/internal — it never appears in the manager's public API, same reasoning as the pilot's `ModConfigBackupsIndex`.

- [ ] **Step 2: Make `ModInstallBackupManager.swift` public, with the injectable init**

Modify `StarHubTH/ModInstallBackupManager.swift`. Change:

```swift
class ModInstallBackupManager {
    static let shared = ModInstallBackupManager()

    enum InstallBackupError: LocalizedError {
        case gameDirEmpty
        case modNotFound(String)
        case backupCreationFailed(String)
        case restoreFailed(String)

        var errorDescription: String? {
            switch self {
            case .gameDirEmpty: return "Game directory is not set."
            case .modNotFound(let folder): return "Mod '\(folder)' not found."
            case .backupCreationFailed(let reason): return "Backup failed: \(reason)"
            case .restoreFailed(let reason): return "Restore failed: \(reason)"
            }
        }
    }
```

to:

```swift
public class ModInstallBackupManager {
    public static let shared = ModInstallBackupManager()

    public enum InstallBackupError: LocalizedError {
        case gameDirEmpty
        case modNotFound(String)
        case backupCreationFailed(String)
        case restoreFailed(String)

        public var errorDescription: String? {
            switch self {
            case .gameDirEmpty: return "Game directory is not set."
            case .modNotFound(let folder): return "Mod '\(folder)' not found."
            case .backupCreationFailed(let reason): return "Backup failed: \(reason)"
            case .restoreFailed(let reason): return "Restore failed: \(reason)"
            }
        }
    }
```

Change the initializer from:

```swift
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        backupsBasePath = appSupport.appendingPathComponent("StarHubTH/Backups/ModInstalls", isDirectory: true)
        backupsDirPath = backupsBasePath.appendingPathComponent("backups", isDirectory: true)
        metadataPath = backupsBasePath.appendingPathComponent("install_metadata.json")
        try? fm.createDirectory(at: backupsDirPath, withIntermediateDirectories: true, attributes: nil)
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
            .appendingPathComponent("StarHubTH/Backups/ModInstalls", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("StarHubTH/Backups/ModInstalls", isDirectory: true)
        backupsBasePath = base
        backupsDirPath = base.appendingPathComponent("backups", isDirectory: true)
        metadataPath = base.appendingPathComponent("install_metadata.json")
        try? fm.createDirectory(at: backupsDirPath, withIntermediateDirectories: true, attributes: nil)
    }
```

Add `public` to every method the tests will call (bodies unchanged):

- `func loadBackups() -> [ModInstallBackup] {` → `public func loadBackups() -> [ModInstallBackup] {`
- `func createBackup(for mod: ModItem, gameDir: String, reason: BackupReason) throws -> ModInstallBackup {` → `public func createBackup(for mod: ModItem, gameDir: String, reason: BackupReason) throws -> ModInstallBackup {`
- `func restoreBackup(_ backup: ModInstallBackup, gameDir: String) throws {` → `public func restoreBackup(_ backup: ModInstallBackup, gameDir: String) throws {`
- `func deleteBackup(_ backup: ModInstallBackup) throws {` → `public func deleteBackup(_ backup: ModInstallBackup) throws {`
- `func cleanupOldBackups() -> Int {` → `public func cleanupOldBackups() -> Int {`

Everything else (`private let fm`, `indexLock`, `withIndexLock`, `loadIndex`, `saveIndex`, `backupDirectory`, `extractMetadata`, `registerSetAsideFolderAsBackup`) stays `private`, unchanged.

- [ ] **Step 3: Verify the main app still builds**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app`.

- [ ] **Step 4: Add the 4 new files to `Package.swift`'s library target, and the new test target**

Modify `Package.swift`. Change:

```swift
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

to:

```swift
        .target(
            name: "StarHubTHCore",
            path: "StarHubTH",
            sources: [
                "ModItem.swift",
                "ModConfigBackup.swift",
                "ModConfigBackupManager.swift",
                "DictionaryExtensions.swift",
                "ZipModInfo.swift",
                "ModInstallBackup.swift",
                "ModInstallBackupManager.swift",
            ]
        ),
        .testTarget(
            name: "ModConfigBackupManagerTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModConfigBackupManagerTests"
        ),
        .testTarget(
            name: "ModInstallBackupManagerTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModInstallBackupManagerTests"
        ),
    ]
)
```

- [ ] **Step 5: Create the test file with shared helpers and one smoke test**

Create `Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift`:

```swift
import Foundation
import Testing
@testable import StarHubTHCore

// MARK: - Test helpers

/// Builds a `ModItem` for tests with sensible defaults — only the fields a
/// given test cares about need to be passed explicitly. This test target
/// gets its own copy of this helper (a separate module from
/// ModConfigBackupManagerTests), matching the same shape for consistency.
func makeTestMod(
    uniqueId: String = "test.mod",
    name: String = "Test Mod",
    folderName: String,
    version: String = "1.0.0",
    isEnabled: Bool = true
) -> ModItem {
    ModItem(
        uniqueId: uniqueId,
        name: name,
        folderName: folderName,
        version: version,
        author: "Test Author",
        description: "",
        nexusUrl: "",
        nexusModId: "",
        isEnabled: isEnabled,
        dependencies: [],
        children: nil,
        isGroup: false,
        installedFileDate: nil
    )
}

/// Writes a UTF-8 text file at `dir/filename`, creating `dir` if needed.
func writeTestFile(in dir: URL, filename: String, content: String = "test content") throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try content.data(using: .utf8)!.write(to: dir.appendingPathComponent(filename))
}

/// Writes a minimal, valid manifest.json that `ModManifest(dict:)` can
/// parse — needed only for tests that exercise the restore-safety-backup
/// path, which reads real metadata off disk (unlike createBackup, which
/// takes metadata straight from the passed-in ModItem).
func writeManifest(in dir: URL, uniqueId: String, name: String, version: String = "1.0.0", author: String = "Test Author") throws {
    let json = """
    {
        "Name": "\(name)",
        "UniqueID": "\(uniqueId)",
        "Version": "\(version)",
        "Author": "\(author)"
    }
    """
    try writeTestFile(in: dir, filename: "manifest.json", content: json)
}

/// Builds a `ModInstallBackup` directly (not through `createBackup`) for
/// `cleanupOldBackups`/`loadBackups` tests that need specific timestamps.
/// `backupPath` is intentionally a nonexistent path — `cleanupOldBackups`
/// already handles a missing on-disk folder gracefully (it only removes
/// the index entry once file removal is confirmed, or the folder was
/// never there to begin with), so fabricated entries are safe to seed.
func makeFakeBackup(timestamp: Date, folderName: String) -> ModInstallBackup {
    ModInstallBackup(
        timestamp: timestamp,
        originalFolderName: folderName,
        backupPath: "/nonexistent/\(folderName)",
        modMetadata: ModMetadata(name: folderName, version: "1.0.0", author: "Test", uniqueId: folderName),
        reason: .beforeInstall
    )
}

/// One isolated test environment: a fresh temp root containing its own
/// `Backups/` (for the manager) and `Game/Mods/` + `Game/Mods_disabled/`
/// (the fake game directory), plus a manager instance pointed at that
/// `Backups/` folder. `cleanup()` must be called (via `defer`) at the end
/// of every test.
struct TestEnvironment {
    let manager: ModInstallBackupManager
    let gameDir: String
    let modsDir: URL
    let modsDisabledDir: URL
    private let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarHubTHTests-\(UUID().uuidString)", isDirectory: true)
        let backupsBase = root.appendingPathComponent("Backups", isDirectory: true)
        let gameDirURL = root.appendingPathComponent("Game", isDirectory: true)
        modsDir = gameDirURL.appendingPathComponent("Mods", isDirectory: true)
        modsDisabledDir = gameDirURL.appendingPathComponent("Mods_disabled", isDirectory: true)
        try? FileManager.default.createDirectory(at: modsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: modsDisabledDir, withIntermediateDirectories: true)
        manager = ModInstallBackupManager(backupsBasePath: backupsBase)
        gameDir = gameDirURL.path
    }

    func cleanup() {
        // Some tests intentionally strip permissions on a path inside
        // `root` to force a deterministic filesystem failure (see the
        // restore-rollback test in Task 5) — restore full permissions
        // recursively first so removeItem can actually delete everything,
        // regardless of which specific subpath a given test locked down.
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["-R", "u+rwX", root.path]
        try? chmod.run()
        chmod.waitUntilExit()
        try? FileManager.default.removeItem(at: root)
    }
}

// MARK: - Tests

@Suite struct ModInstallBackupManagerTests {

    @Test func freshEnvironmentHasNoBackups() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        #expect(env.manager.loadBackups().isEmpty)
    }
}
```

- [ ] **Step 6: Run the smoke test**

Run: `./run_tests.sh`
Expected: output shows both `ModConfigBackupManagerTests` (14 tests, from the pilot, including its post-final-review fix `restoreBackupPreservesNestedPackPathOnRoundTrip`) and the new `ModInstallBackupManagerTests` (1 test) suites passing.

- [ ] **Step 7: Commit**

```bash
git add Package.swift StarHubTH/ModInstallBackup.swift StarHubTH/ModInstallBackupManager.swift Tests/ModInstallBackupManagerTests/
git commit -m "test: stand up SPM test target for ModInstallBackupManager

Adds ModInstallBackup.swift, ModInstallBackupManager.swift,
DictionaryExtensions.swift, and ZipModInfo.swift to the existing
StarHubTHCore library target's sources, and a new
ModInstallBackupManagerTests test target. Makes ModInstallBackupManager
and its model types public with an injectable backupsBasePath, same
pattern as the pilot. One smoke test proves the pipeline compiles and
links."
```

---

### Task 3: `createBackup` — enabled/disabled source folders + error cases

**Files:**
- Modify: `Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `makeTestMod`, `writeTestFile` (Task 2).

- [ ] **Step 1: Add the four tests**

Add inside `@Suite struct ModInstallBackupManagerTests { ... }`, after `freshEnvironmentHasNoBackups`:

```swift
    @Test func createBackupCopiesEnabledModFromModsFolder() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let modDir = env.modsDir.appendingPathComponent("EnabledMod", isDirectory: true)
        try writeTestFile(in: modDir, filename: "data.txt", content: "hello")

        let mod = makeTestMod(folderName: "EnabledMod", isEnabled: true)
        let backup = try env.manager.createBackup(for: mod, gameDir: env.gameDir, reason: .beforeInstall)

        #expect(backup.originalFolderName == "EnabledMod")
        #expect(backup.reason == .beforeInstall)
        let copiedContent = try String(contentsOf: URL(fileURLWithPath: backup.backupPath).appendingPathComponent("data.txt"), encoding: .utf8)
        #expect(copiedContent == "hello")
        #expect(env.manager.loadBackups().count == 1)
    }

    @Test func createBackupCopiesDisabledModFromModsDisabledFolder() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let modDir = env.modsDisabledDir.appendingPathComponent("DisabledMod", isDirectory: true)
        try writeTestFile(in: modDir, filename: "data.txt", content: "hello")

        let mod = makeTestMod(folderName: "DisabledMod", isEnabled: false)
        let backup = try env.manager.createBackup(for: mod, gameDir: env.gameDir, reason: .beforeUpdate)

        #expect(backup.originalFolderName == "DisabledMod")
        let copiedContent = try String(contentsOf: URL(fileURLWithPath: backup.backupPath).appendingPathComponent("data.txt"), encoding: .utf8)
        #expect(copiedContent == "hello")
    }

    @Test func createBackupThrowsWhenModFolderNotFound() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let mod = makeTestMod(folderName: "NonexistentMod")

        do {
            _ = try env.manager.createBackup(for: mod, gameDir: env.gameDir, reason: .beforeInstall)
            Issue.record("Expected createBackup to throw .modNotFound")
        } catch ModInstallBackupManager.InstallBackupError.modNotFound(let folder) {
            #expect(folder == "NonexistentMod")
        } catch {
            Issue.record("Expected .modNotFound, got \(error)")
        }
    }

    @Test func createBackupThrowsWhenGameDirEmpty() {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let mod = makeTestMod(folderName: "AnyMod")

        do {
            _ = try env.manager.createBackup(for: mod, gameDir: "", reason: .beforeInstall)
            Issue.record("Expected createBackup to throw .gameDirEmpty")
        } catch ModInstallBackupManager.InstallBackupError.gameDirEmpty {
            // expected
        } catch {
            Issue.record("Expected .gameDirEmpty, got \(error)")
        }
    }
```

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `ModInstallBackupManagerTests` suite shows 5 tests passing.

- [ ] **Step 3: Commit**

```bash
git add Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift
git commit -m "test: cover createBackup for enabled/disabled mods and error cases"
```

---

### Task 4: `restoreBackup` — basic copy + replace-and-register

**Files:**
- Modify: `Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `makeTestMod`, `writeTestFile`, `writeManifest` (Task 2).

- [ ] **Step 1: Add the two tests**

```swift
    @Test func restoreBackupCopiesToEmptyDestination() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let modDir = env.modsDir.appendingPathComponent("RestoreMod", isDirectory: true)
        try writeTestFile(in: modDir, filename: "data.txt", content: "original")

        let mod = makeTestMod(folderName: "RestoreMod", isEnabled: true)
        let backup = try env.manager.createBackup(for: mod, gameDir: env.gameDir, reason: .beforeInstall)

        // Destination (Mods_disabled/RestoreMod) doesn't exist yet.
        try env.manager.restoreBackup(backup, gameDir: env.gameDir)

        let restoredPath = env.modsDisabledDir.appendingPathComponent("RestoreMod/data.txt")
        let restoredContent = try String(contentsOf: restoredPath, encoding: .utf8)
        #expect(restoredContent == "original")
    }

    @Test func restoreBackupReplacesExistingFolderAndRegistersItAsNewBackup() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let modDir = env.modsDir.appendingPathComponent("RestoreMod", isDirectory: true)
        try writeTestFile(in: modDir, filename: "data.txt", content: "original")

        let mod = makeTestMod(folderName: "RestoreMod", isEnabled: true)
        let backup = try env.manager.createBackup(for: mod, gameDir: env.gameDir, reason: .beforeInstall)

        // A different version is already sitting at the live destination,
        // with a real manifest.json so the replaced-version registration
        // (which reads metadata off disk) can succeed.
        let liveDestDir = env.modsDisabledDir.appendingPathComponent("RestoreMod", isDirectory: true)
        try writeTestFile(in: liveDestDir, filename: "data.txt", content: "currently live")
        try writeManifest(in: liveDestDir, uniqueId: "restore.mod", name: "Restore Mod", version: "2.0.0")

        try env.manager.restoreBackup(backup, gameDir: env.gameDir)

        let restoredContent = try String(contentsOf: liveDestDir.appendingPathComponent("data.txt"), encoding: .utf8)
        #expect(restoredContent == "original")

        // The replaced ("currently live") version must now be registered
        // as its own backup rather than discarded, so the restore is
        // itself undoable.
        let allBackups = env.manager.loadBackups()
        #expect(allBackups.count == 2)
        let registered = allBackups.first { $0.id != backup.id }
        #expect(registered?.reason == .beforeRestore)
        #expect(registered?.modMetadata.uniqueId == "restore.mod")
        #expect(registered?.modMetadata.version == "2.0.0")
    }
```

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `ModInstallBackupManagerTests` suite shows 7 tests passing.

- [ ] **Step 3: Commit**

```bash
git add Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift
git commit -m "test: cover restoreBackup's basic copy and replace-and-register paths"
```

---

### Task 5: `restoreBackup` — rollback on copy failure + missing backup folder

This is the highest-value task in this plan: it regression-covers this
session's Critical audit fix (restore must not lose the live mod if the
copy-from-backup step fails partway through).

**Files:**
- Modify: `Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `makeTestMod`, `writeTestFile` (Task 2).

- [ ] **Step 1: Add the two tests**

```swift
    @Test func restoreBackupRollsBackOnCopyFailure() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let modDir = env.modsDir.appendingPathComponent("RestoreMod", isDirectory: true)
        try writeTestFile(in: modDir, filename: "data.txt", content: "original")

        let mod = makeTestMod(folderName: "RestoreMod", isEnabled: true)
        let backup = try env.manager.createBackup(for: mod, gameDir: env.gameDir, reason: .beforeInstall)

        let liveDestDir = env.modsDisabledDir.appendingPathComponent("RestoreMod", isDirectory: true)
        try writeTestFile(in: liveDestDir, filename: "data.txt", content: "currently live")

        // Strip all permissions from the backup's own source folder so the
        // copy-from-backup step fails deterministically — *after* the
        // live folder has already been moved aside (a normal, permitted
        // move within Mods_disabled, since only the backup source is
        // locked down, not Mods_disabled itself). This reproduces exactly
        // the failure window the rollback protects against. Verified
        // empirically that a 0-permission source directory makes a
        // recursive copy fail (`cp -R` against it exits non-zero with
        // "Permission denied").
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: backup.backupPath)

        do {
            try env.manager.restoreBackup(backup, gameDir: env.gameDir)
            Issue.record("Expected restoreBackup to throw .restoreFailed")
        } catch ModInstallBackupManager.InstallBackupError.restoreFailed {
            // expected
        } catch {
            Issue.record("Expected .restoreFailed, got \(error)")
        }

        // The rollback must have moved the live folder back into place —
        // reading it doesn't require write access to its parent, so this
        // assertion is valid even while the backup source is still locked.
        let restoredContent = try String(contentsOf: liveDestDir.appendingPathComponent("data.txt"), encoding: .utf8)
        #expect(restoredContent == "currently live")
    }

    @Test func restoreBackupThrowsWhenBackupFolderMissing() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let modDir = env.modsDir.appendingPathComponent("RestoreMod", isDirectory: true)
        try writeTestFile(in: modDir, filename: "data.txt", content: "original")

        let mod = makeTestMod(folderName: "RestoreMod", isEnabled: true)
        let backup = try env.manager.createBackup(for: mod, gameDir: env.gameDir, reason: .beforeInstall)

        // Delete the backup's own on-disk folder without going through
        // deleteBackup, simulating external/corrupted state.
        try FileManager.default.removeItem(atPath: backup.backupPath)

        do {
            try env.manager.restoreBackup(backup, gameDir: env.gameDir)
            Issue.record("Expected restoreBackup to throw .restoreFailed")
        } catch ModInstallBackupManager.InstallBackupError.restoreFailed {
            // expected
        } catch {
            Issue.record("Expected .restoreFailed, got \(error)")
        }

        // No live folder should have been created.
        #expect(!FileManager.default.fileExists(atPath: env.modsDisabledDir.appendingPathComponent("RestoreMod").path))
    }
```

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `ModInstallBackupManagerTests` suite shows 9 tests passing.

- [ ] **Step 3: Verify the empirical claim about permission-based copy failure holds on this machine**

Run:
```bash
rm -rf /tmp/plan-chmod-check && mkdir -p /tmp/plan-chmod-check/src/inner && echo hi > /tmp/plan-chmod-check/src/inner/f.txt && chmod 000 /tmp/plan-chmod-check/src && mkdir -p /tmp/plan-chmod-check/dest && cp -R /tmp/plan-chmod-check/src /tmp/plan-chmod-check/dest/src; echo "exit:$?"; chmod -R u+rwX /tmp/plan-chmod-check && rm -rf /tmp/plan-chmod-check
```
Expected: `exit:1` with a "Permission denied" message — confirms the technique `restoreBackupRollsBackOnCopyFailure` relies on. If this doesn't reproduce the failure on the machine running this plan, stop and report — the test's premise needs re-examining rather than being force-committed.

- [ ] **Step 4: Commit**

```bash
git add Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift
git commit -m "test: regression-cover restoreBackup's copy-failure rollback

This is the Critical fix from the July 2026 audit: if the copy-from-
backup step fails after the live folder was already moved aside, the
live folder must be moved back rather than left missing."
```

---

### Task 6: `deleteBackup` + folder-name uniqueness

**Files:**
- Modify: `Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `makeTestMod`, `writeTestFile` (Task 2).

- [ ] **Step 1: Add the two tests**

```swift
    @Test func deleteBackupRemovesFolderAndIndexEntry() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let modDir = env.modsDir.appendingPathComponent("DeleteMod", isDirectory: true)
        try writeTestFile(in: modDir, filename: "data.txt")

        let mod = makeTestMod(folderName: "DeleteMod")
        let backup = try env.manager.createBackup(for: mod, gameDir: env.gameDir, reason: .beforeInstall)
        #expect(env.manager.loadBackups().count == 1)
        #expect(FileManager.default.fileExists(atPath: backup.backupPath))

        try env.manager.deleteBackup(backup)

        #expect(env.manager.loadBackups().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: backup.backupPath))
    }

    @Test func twoBackupsCreatedBackToBackGetDistinctFolderNames() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let modDir = env.modsDir.appendingPathComponent("SameSecondMod", isDirectory: true)
        try writeTestFile(in: modDir, filename: "data.txt")

        let mod = makeTestMod(folderName: "SameSecondMod")
        let first = try env.manager.createBackup(for: mod, gameDir: env.gameDir, reason: .beforeInstall)
        let second = try env.manager.createBackup(for: mod, gameDir: env.gameDir, reason: .beforeInstall)

        #expect(first.backupPath != second.backupPath)
        #expect(env.manager.loadBackups().count == 2)

        try env.manager.deleteBackup(first)
        #expect(env.manager.loadBackups().count == 1)
        #expect(env.manager.loadBackups()[0].id == second.id)
        #expect(FileManager.default.fileExists(atPath: second.backupPath))
    }
```

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `ModInstallBackupManagerTests` suite shows 11 tests passing.

- [ ] **Step 3: Commit**

```bash
git add Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift
git commit -m "test: cover deleteBackup and same-second folder-name uniqueness"
```

---

### Task 7: `cleanupOldBackups` — 5-backup floor + 30-day window (isolated from each other)

Adds the same kind of internal test-seeding seam the pilot added in its
Task 8, for the same reason: `cleanupOldBackups` computes its cutoff from
the real `Date()`, so testing it needs fabricated timestamps. Unlike the
pilot's two cleanup tests (whose final review flagged that they didn't
isolate the 30-day-window tier from the 5-backup floor), this task's two
tests are deliberately built so each tier is tested independently of the
other.

**Files:**
- Modify: `StarHubTH/ModInstallBackupManager.swift` (add `seedIndexForTesting`)
- Modify: `Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `makeFakeBackup` (Task 2).
- Produces: `func seedIndexForTesting(with backups: [ModInstallBackup])` (internal) on `ModInstallBackupManager`.

- [ ] **Step 1: Add the seeding method**

In `StarHubTH/ModInstallBackupManager.swift`, add this method in the `// MARK: - Index` section, right after `saveIndex`:

```swift
    /// Test-only seam (visible via `@testable import`) for seeding the
    /// index with pre-fabricated backups — lets tests exercise
    /// timestamp-dependent logic (like `cleanupOldBackups`'s retention
    /// tiers) without waiting real time or injecting a fake clock.
    /// Deliberately left internal (not `public`) — invisible to any real
    /// consumer of this library.
    func seedIndexForTesting(with backups: [ModInstallBackup]) {
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
            makeFakeBackup(timestamp: veryOld.addingTimeInterval(Double(i)), folderName: "fake-\(i)")
        }
        env.manager.seedIndexForTesting(with: fabricated)
        #expect(env.manager.loadBackups().count == 6)

        let deletedCount = env.manager.cleanupOldBackups()

        // All 6 share one calendar month and are >30 days old, so tier 3
        // (most-recent-per-month) protects only the same one entry tier 1
        // already protects — net: exactly 1 of the 6 (the single least
        // recent) is eligible for deletion.
        #expect(deletedCount == 1)
        #expect(env.manager.loadBackups().count == 5)
    }

    @Test func cleanupOldBackupsKeepsEverythingWithin30DaysRegardlessOfFloor() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let now = Date()
        // 8 backups, all within the last 7 days (well inside the 30-day
        // window) — more than the 5-backup floor, but none should be
        // deleted, since this test isolates the 30-day-window tier: an
        // implementation that ignored the window and only kept 5 would
        // fail this test by deleting 3.
        let fabricated = (0..<8).map { i in
            makeFakeBackup(timestamp: now.addingTimeInterval(Double(-i) * 24 * 60 * 60), folderName: "recent-\(i)")
        }
        env.manager.seedIndexForTesting(with: fabricated)

        let deletedCount = env.manager.cleanupOldBackups()

        #expect(deletedCount == 0)
        #expect(env.manager.loadBackups().count == 8)
    }
```

- [ ] **Step 3: Run the tests**

Run: `./run_tests.sh`
Expected: `ModInstallBackupManagerTests` suite shows 13 tests passing.

- [ ] **Step 4: Verify the main app still builds**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app` (this task touched production code).

- [ ] **Step 5: Commit**

```bash
git add StarHubTH/ModInstallBackupManager.swift Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift
git commit -m "test: cover cleanupOldBackups' floor and 30-day-window tiers in isolation

Adds an internal (not public) seedIndexForTesting seam, reachable only
via @testable import. Unlike the pilot's equivalent tests (flagged by
its final review for not isolating the two tiers), the second test
here uses backups that are ALL within 30 days despite exceeding the
5-backup floor, so a broken implementation that ignored the window
would fail it."
```

---

### Task 8: `cleanupOldBackups` — most-recent-per-calendar-month tier

The most complex test in this plan: `cleanupOldBackups`'s 3rd retention
tier (beyond 30 days, keep the most recent backup per calendar month).
Never covered by a test before this task.

**Files:**
- Modify: `Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `makeFakeBackup`, `seedIndexForTesting` (Tasks 2, 7).

- [ ] **Step 1: Add the test**

```swift
    @Test func cleanupOldBackupsKeepsMostRecentPerCalendarMonthBeyond30Days() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let calendar = Calendar(identifier: .gregorian)
        let nowComponents = calendar.dateComponents([.year, .month], from: Date())
        let currentYear = nowComponents.year!
        let currentMonth = nowComponents.month!

        // Returns the (year, month) that is `n` calendar months before the
        // current one. Used to build 3 distinct months, each anchored on a
        // FIXED day-of-month (15th / 5th below) rather than "today minus N
        // days" — this makes the test's month boundaries deterministic
        // regardless of what day of the month it happens to run on (a
        // "today minus 5 days" approach could accidentally cross into the
        // previous month depending on today's date, which would silently
        // break the "2 entries in the same month" setup this test relies
        // on).
        func monthsAgo(_ n: Int) -> (year: Int, month: Int) {
            let totalMonths = currentYear * 12 + (currentMonth - 1) - n
            let year = totalMonths / 12
            let month = totalMonths % 12 + 1
            return (year, month)
        }

        // 3 distinct calendar months, each comfortably more than 30 days
        // before now (6, 7, 8 months back), each with 2 entries: a
        // "recent" one (day 15) and an "older" one (day 5) — only the
        // "recent" one of each pair should survive tier 3.
        var fabricated: [ModInstallBackup] = []
        for (index, n) in [6, 7, 8].enumerated() {
            let (year, month) = monthsAgo(n)
            let recentDate = calendar.date(from: DateComponents(year: year, month: month, day: 15, hour: 12))!
            let olderDate = calendar.date(from: DateComponents(year: year, month: month, day: 5, hour: 12))!
            fabricated.append(makeFakeBackup(timestamp: recentDate, folderName: "month\(index)-recent"))
            fabricated.append(makeFakeBackup(timestamp: olderDate, folderName: "month\(index)-older"))
        }

        // Plus 5 backups from "now" to satisfy the 5-most-recent floor
        // without interfering with the month-tier assertions below (they
        // land in the current month, entirely separate from the 3
        // fabricated past months).
        let now = Date()
        for i in 0..<5 {
            fabricated.append(makeFakeBackup(timestamp: now.addingTimeInterval(Double(-i)), folderName: "floor-\(i)"))
        }

        env.manager.seedIndexForTesting(with: fabricated)
        #expect(env.manager.loadBackups().count == 11)

        let deletedCount = env.manager.cleanupOldBackups()

        // 6 fabricated "beyond 30 days" entries in, 3 survive (the more
        // recent of each month's pair) — 3 deleted. The 5 "floor" entries
        // all survive (protected by both the floor and the 30-day window).
        #expect(deletedCount == 3)
        let survivingNames = Set(env.manager.loadBackups().map { $0.originalFolderName })
        #expect(survivingNames == Set([
            "floor-0", "floor-1", "floor-2", "floor-3", "floor-4",
            "month0-recent", "month1-recent", "month2-recent",
        ]))
    }
```

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `ModInstallBackupManagerTests` suite shows 14 tests passing.

- [ ] **Step 3: Commit**

```bash
git add Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift
git commit -m "test: cover cleanupOldBackups' most-recent-per-calendar-month tier

The 3rd and most complex retention tier, never covered by a test
before. Uses fixed days-of-month (15th/5th) rather than relative
offsets so the test's month boundaries can't accidentally shift
depending on what day it's run on."
```

---

### Task 9: `loadBackups` sort order

**Files:**
- Modify: `Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `makeFakeBackup`, `seedIndexForTesting` (Tasks 2, 7).

- [ ] **Step 1: Add the test**

```swift
    @Test func loadBackupsReturnsNewestFirst() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let now = Date()
        let fabricated = [
            makeFakeBackup(timestamp: now.addingTimeInterval(-100), folderName: "oldest"),
            makeFakeBackup(timestamp: now, folderName: "newest"),
            makeFakeBackup(timestamp: now.addingTimeInterval(-50), folderName: "middle"),
        ]
        env.manager.seedIndexForTesting(with: fabricated)

        let loaded = env.manager.loadBackups()

        #expect(loaded.map(\.originalFolderName) == ["newest", "middle", "oldest"])
    }
```

- [ ] **Step 2: Run the full suite one last time**

Run: `./run_tests.sh`
Expected: `ModInstallBackupManagerTests` suite shows 15 tests passing (alongside the pilot's `ModConfigBackupManagerTests` suite, unaffected).

- [ ] **Step 3: Final full verification**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app`.

- [ ] **Step 4: Commit**

```bash
git add Tests/ModInstallBackupManagerTests/ModInstallBackupManagerTests.swift
git commit -m "test: cover loadBackups' newest-first sort order

ModInstallBackupManager test extension complete: 15 tests covering
create, restore (including the Critical rollback fix), delete,
cleanup (all 3 retention tiers, tested in isolation from each other),
and load."
```
