# SaveManager Folder-Operations Test Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the automated-test pattern established by the `ModConfigBackupManager` pilot and its `ModInstallBackupManager` extension to `SaveManager`'s folder-operation surface (backup/restore/delete/duplicate/branch a save), fixing a discovered same-second folder-naming collision bug along the way.

**Architecture:** Reuses the existing `Package.swift`/`StarHubTHCore` library target (add 3 more files to its `sources:`) and adds a new, separate Swift Testing test target `SaveManagerTests`. `build_app.py` is untouched. Unlike the previous two managers, no dependency-injection changes are needed — every method in scope operates on `URL`s supplied via its parameters, never `SaveManager`'s internal `savesDir`.

**Tech Stack:** Swift 6.3 toolchain, Swift Package Manager, Swift Testing.

## Global Constraints

- No change to `build_app.py`'s build output or behavior.
- No change to `SaveManager`'s production behavior beyond the one approved fix (folder-naming uniqueness + the parsing adjustment it requires).
- Tests must never touch the real `~/.config/StardewValley/Saves` directory.
- Test framework: Swift Testing.
- Known, accepted limitation (per the approved spec): `deleteSave`/`deleteBackup` tests cannot verify or clean up the real Trash destination, since production code calls `FileManager.trashItem(at:resultingItemURL: nil)` and discards that information. Tests instead assert the item is gone from its *original* location. Small, inert debris in the real system Trash is an accepted side effect, not a bug to fix here.

**Two corrections to the approved spec, discovered during planning:**

1. The spec suggested `SaveGameInfo`'s computed properties (`farmTypeName`, `farmIcon`, `seasonName`) don't need anything added since tests don't call them. That's true for their *visibility*, but `seasonName`'s implementation references `L10n.Saves.spring`/`.summer`/`.fall`/`.winter` directly — since Swift compiles a type's full body regardless of which members a test actually calls, `L10n.swift` **must** be added to the library target's `sources:` for `SaveManager.swift` to compile at all, even though tests never touch `seasonName`. `L10n.swift` has zero imports and no dependencies, so this is a safe, no-risk addition — it does not need to be `public`, since nothing in the public API surface exposes it.
2. The spec described `duplicateSave` called twice as producing `"_copy"` then `"_copy_2"`. Re-reading `cloneSaveFolder`'s actual collision loop (`StarHubTH/SaveManager.swift:551-559`) shows the counter starts at `1` and is appended directly (not incrementing an implicit `_0`), so the second call actually produces `"_copy_1"`, not `"_copy_2"`. Task 7 below uses the corrected name.

---

### Task 1: Add `SaveManager.swift` to the SPM target, visibility changes, new test target + smoke test

**Files:**
- Modify: `Package.swift`
- Modify: `StarHubTH/SaveManager.swift` (visibility only — no behavior change in this task)
- Create: `Tests/SaveManagerTests/SaveManagerTests.swift`

**Interfaces:**
- Produces: `public struct SaveGameInfo` and `public struct SaveBackup`, both with explicit `public init(...)` (parameter order matches every existing call site exactly, verified against `parseSaveFile`'s and `listBackups`' actual constructor calls — a safe drop-in for the implicit memberwise init). `public class SaveManager` with `public static let shared` and every method later tasks call (`backupSave`, `deleteSave`, `duplicateSave`, `branchFromBackup`, `listBackups`, `restoreBackup`, `deleteBackup`) marked `public`. Test-file helpers `makeTestSave(...)`, `writeTestSaveFile(at:content:)`, and `struct TestEnvironment` (properties: `savesDir: URL`; methods: `makeSave(named:content:) throws -> SaveGameInfo`, `cleanup()`) — every later task's tests use these exact names/signatures.

- [ ] **Step 1: Make `SaveGameInfo` public**

Modify `StarHubTH/SaveManager.swift`. Change:

```swift
struct SaveGameInfo: Identifiable, Equatable, Hashable {
    var id: String { folderName }
    let folderName: String
    let fileURL: URL
    let lastModified: Date
    
    var playerName: String
    var farmName: String
    var favoriteThing: String
    var money: Int
    var spouse: String   // empty string = single (no <spouse> tag)
    
    // Advanced Stats
    var maxHealth: Int
    var maxStamina: Int
    var goldenWalnuts: Int
    var qiGems: Int
    var clubCoins: Int
    var totalMoneyEarned: Int
    
    var year: Int
    var season: Int
    var day: Int
    var whichFarm: Int
    
    var farmTypeName: String {
```

to:

```swift
public struct SaveGameInfo: Identifiable, Equatable, Hashable {
    public var id: String { folderName }
    public let folderName: String
    public let fileURL: URL
    public let lastModified: Date

    public var playerName: String
    public var farmName: String
    public var favoriteThing: String
    public var money: Int
    public var spouse: String   // empty string = single (no <spouse> tag)

    // Advanced Stats
    public var maxHealth: Int
    public var maxStamina: Int
    public var goldenWalnuts: Int
    public var qiGems: Int
    public var clubCoins: Int
    public var totalMoneyEarned: Int

    public var year: Int
    public var season: Int
    public var day: Int
    public var whichFarm: Int

    public init(
        folderName: String,
        fileURL: URL,
        lastModified: Date,
        playerName: String,
        farmName: String,
        favoriteThing: String,
        money: Int,
        spouse: String,
        maxHealth: Int,
        maxStamina: Int,
        goldenWalnuts: Int,
        qiGems: Int,
        clubCoins: Int,
        totalMoneyEarned: Int,
        year: Int,
        season: Int,
        day: Int,
        whichFarm: Int
    ) {
        self.folderName = folderName
        self.fileURL = fileURL
        self.lastModified = lastModified
        self.playerName = playerName
        self.farmName = farmName
        self.favoriteThing = favoriteThing
        self.money = money
        self.spouse = spouse
        self.maxHealth = maxHealth
        self.maxStamina = maxStamina
        self.goldenWalnuts = goldenWalnuts
        self.qiGems = qiGems
        self.clubCoins = clubCoins
        self.totalMoneyEarned = totalMoneyEarned
        self.year = year
        self.season = season
        self.day = day
        self.whichFarm = whichFarm
    }

    var farmTypeName: String {
```

Leave `farmTypeName`, `farmIcon`, and `seasonName` (and their bodies) exactly as they are — not `public`, since no test needs them, but their implementations must still compile, which is why `L10n.swift` is added to `sources:` in Step 4 below.

- [ ] **Step 2: Make `SaveBackup` public**

Change:

```swift
struct SaveBackup: Identifiable, Equatable {
    var id: String { folderPath.path }
    let folderPath: URL
    let timestamp: Date
    let saveFolder: String   // parent save folder name
}
```

to:

```swift
public struct SaveBackup: Identifiable, Equatable {
    public var id: String { folderPath.path }
    public let folderPath: URL
    public let timestamp: Date
    public let saveFolder: String   // parent save folder name

    public init(folderPath: URL, timestamp: Date, saveFolder: String) {
        self.folderPath = folderPath
        self.timestamp = timestamp
        self.saveFolder = saveFolder
    }
}
```

- [ ] **Step 3: Make `SaveManager` and its methods public**

Change:

```swift
class SaveManager {
    static let shared = SaveManager()
```

to:

```swift
public class SaveManager {
    public static let shared = SaveManager()
```

Change the initializer from:

```swift
    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.savesDir = homeDir.appendingPathComponent(".config/StardewValley/Saves")
    }
```

to:

```swift
    public init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.savesDir = homeDir.appendingPathComponent(".config/StardewValley/Saves")
    }
```

(No parameter added — every method this plan tests operates on the `URL`s passed via its `SaveGameInfo`/`SaveBackup` arguments, never `self.savesDir`, so no injectable override is needed here.)

Add `public` to each of these method signatures (bodies unchanged):

- `func backupSave(info: SaveGameInfo) -> Bool {` → `public func backupSave(info: SaveGameInfo) -> Bool {`
- `func deleteSave(info: SaveGameInfo) -> Bool {` → `public func deleteSave(info: SaveGameInfo) -> Bool {`
- `func duplicateSave(info: SaveGameInfo, newName: String, newFarm: String) -> Bool {` → `public func duplicateSave(info: SaveGameInfo, newName: String, newFarm: String) -> Bool {`
- `func branchFromBackup(backup: SaveBackup, newName: String, newFarm: String) -> Bool {` → `public func branchFromBackup(backup: SaveBackup, newName: String, newFarm: String) -> Bool {`
- `func listBackups(for info: SaveGameInfo) -> [SaveBackup] {` → `public func listBackups(for info: SaveGameInfo) -> [SaveBackup] {`
- `func restoreBackup(backup: SaveBackup, info: SaveGameInfo) -> Bool {` → `public func restoreBackup(backup: SaveBackup, info: SaveGameInfo) -> Bool {`
- `func deleteBackup(_ backup: SaveBackup) -> Bool {` → `public func deleteBackup(_ backup: SaveBackup) -> Bool {`

Everything else (`cloneSaveFolder`, `modifyInternalSaveNames`, `extractTag`, `extractSpouseFromPlayer`, `updateSpouseInPlayer`, `replaceOrRemoveSpouseTag`, `cleanDivorceNPCFriendship*`, `replaceFirstTag*`, `cachedRegex`, `regexCache`, `regexCacheLock`, `fetchSaves`, `parseSaveFile`, `updateSave`, `fetchInventory`, `updateInventory`, `openSaveInFinder`, `modifyInternalSaveNames`) stays exactly as it is — `private` or plain `internal`, unchanged. (`fetchSaves`/`parseSaveFile`/`updateSave`/`fetchInventory`/`updateInventory` are out of scope for this plan — a future spec covers them.)

- [ ] **Step 4: Verify the main app still builds**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app`.

- [ ] **Step 5: Add `SaveManager.swift`, `Models/InventoryItem.swift`, and `L10n.swift` to `Package.swift`, and the new test target**

Modify `Package.swift`. Change:

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
                "SaveManager.swift",
                "Models/InventoryItem.swift",
                "L10n.swift",
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
        .testTarget(
            name: "SaveManagerTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/SaveManagerTests"
        ),
    ]
)
```

- [ ] **Step 6: Create the test file with shared helpers and one smoke test**

Create `Tests/SaveManagerTests/SaveManagerTests.swift`:

```swift
import Foundation
import Testing
@testable import StarHubTHCore

// MARK: - Test helpers

/// Builds a `SaveGameInfo` for tests with sensible defaults — only
/// `folderName`/`fileURL` need to be set per test (every test controls
/// where its fake save file lives).
func makeTestSave(
    folderName: String,
    fileURL: URL,
    lastModified: Date = Date(),
    playerName: String = "TestPlayer",
    farmName: String = "TestFarm",
    favoriteThing: String = "",
    money: Int = 500,
    spouse: String = "",
    maxHealth: Int = 100,
    maxStamina: Int = 270,
    goldenWalnuts: Int = 0,
    qiGems: Int = 0,
    clubCoins: Int = 0,
    totalMoneyEarned: Int = 500,
    year: Int = 1,
    season: Int = 0,
    day: Int = 1,
    whichFarm: Int = 0
) -> SaveGameInfo {
    SaveGameInfo(
        folderName: folderName,
        fileURL: fileURL,
        lastModified: lastModified,
        playerName: playerName,
        farmName: farmName,
        favoriteThing: favoriteThing,
        money: money,
        spouse: spouse,
        maxHealth: maxHealth,
        maxStamina: maxStamina,
        goldenWalnuts: goldenWalnuts,
        qiGems: qiGems,
        clubCoins: clubCoins,
        totalMoneyEarned: totalMoneyEarned,
        year: year,
        season: season,
        day: day,
        whichFarm: whichFarm
    )
}

/// Writes a UTF-8 text file at `url`, creating its parent directory if
/// needed.
func writeTestSaveFile(at url: URL, content: String = "test save content") throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try content.data(using: .utf8)!.write(to: url)
}

/// One isolated test environment: a fresh temp root containing a
/// `Saves/` folder, mirroring the real on-disk shape closely enough for
/// SaveManager's folder-operation methods (which never read
/// `SaveManager`'s own `savesDir` — every method operates on the URLs
/// passed via its `SaveGameInfo`/`SaveBackup` arguments). `cleanup()`
/// must be called (via `defer`) at the end of every test.
struct TestEnvironment {
    let savesDir: URL
    private let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarHubTHTests-\(UUID().uuidString)", isDirectory: true)
        savesDir = root.appendingPathComponent("Saves", isDirectory: true)
        try? FileManager.default.createDirectory(at: savesDir, withIntermediateDirectories: true)
    }

    /// Creates `Saves/<name>/<name>` (a save's XML file shares its
    /// folder's name, matching the real layout) with the given content,
    /// and returns a `SaveGameInfo` pointing at it.
    func makeSave(named name: String, content: String = "test save content") throws -> SaveGameInfo {
        let folderURL = savesDir.appendingPathComponent(name, isDirectory: true)
        let fileURL = folderURL.appendingPathComponent(name)
        try writeTestSaveFile(at: fileURL, content: content)
        return makeTestSave(folderName: name, fileURL: fileURL)
    }

    func cleanup() {
        // A later task's rollback test locks down a path inside `root` —
        // restore full permissions recursively first so removeItem can
        // actually delete everything, regardless of which specific
        // subpath got locked down.
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["-R", "u+rwX", root.path]
        try? chmod.run()
        chmod.waitUntilExit()
        try? FileManager.default.removeItem(at: root)
    }
}

// MARK: - Tests

@Suite struct SaveManagerTests {

    @Test func makeTestSaveBuildsAValidSaveGameInfo() {
        let save = makeTestSave(folderName: "SmokeTest", fileURL: URL(fileURLWithPath: "/tmp/SmokeTest/SmokeTest"))
        #expect(save.folderName == "SmokeTest")
        #expect(save.playerName == "TestPlayer")
    }
}
```

- [ ] **Step 7: Run the smoke test**

Run: `./run_tests.sh`
Expected: output shows `ModConfigBackupManagerTests` (14 tests), `ModInstallBackupManagerTests` (15 tests), and the new `SaveManagerTests` (1 test) suites all passing — 30 total.

- [ ] **Step 8: Commit**

```bash
git add Package.swift StarHubTH/SaveManager.swift Tests/SaveManagerTests/
git commit -m "test: stand up SPM test target for SaveManager

Adds SaveManager.swift, Models/InventoryItem.swift, and L10n.swift to
the existing StarHubTHCore library target's sources (L10n.swift is
needed only because SaveGameInfo.seasonName's body references it, even
though this plan's tests never call that property), and a new
SaveManagerTests test target. Makes SaveGameInfo, SaveBackup, and
SaveManager's folder-operation methods public — no injectable
directory override needed, since none of the methods this plan tests
read SaveManager's own savesDir. One smoke test proves the pipeline
compiles and links."
```

---

### Task 2: Fix the same-second backup-naming collision + regression tests

**Files:**
- Modify: `StarHubTH/SaveManager.swift` (the approved bug fix)
- Modify: `Tests/SaveManagerTests/SaveManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `writeTestSaveFile` (Task 1).

This fixes all three locations that share the same latent bug together,
since they're interdependent: `backupSave`'s and `restoreBackup`'s
pre-restore-backup naming (no uniqueness suffix — a same-second collision
silently fails the backup) and `listBackups`' matching parse logic (a
uniqueness suffix appended after the timestamp would otherwise break its
strict-format date parsing).

- [ ] **Step 1: Fix `backupSave`'s naming**

Change:

```swift
    func backupSave(info: SaveGameInfo) -> Bool {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        
        let folderPath = info.fileURL.deletingLastPathComponent()
        let backupPath = folderPath.appendingPathExtension("backup_\(timestamp)")
```

to:

```swift
    func backupSave(info: SaveGameInfo) -> Bool {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        
        let folderPath = info.fileURL.deletingLastPathComponent()
        // A UUID suffix guarantees each backup gets its own folder even
        // when several are created within the same second — without it,
        // the copyItem below fails (destination exists) and backupSave
        // silently returns false.
        let backupPath = folderPath.appendingPathExtension("backup_\(timestamp)_\(UUID().uuidString)")
```

- [ ] **Step 2: Fix `restoreBackup`'s pre-restore backup naming**

Change:

```swift
        let preRestoreBackupPath = saveFolder
            .deletingLastPathComponent()
            .appendingPathComponent("\(saveFolder.lastPathComponent).backup_\(timestamp)")
```

to:

```swift
        let preRestoreBackupPath = saveFolder
            .deletingLastPathComponent()
            .appendingPathComponent("\(saveFolder.lastPathComponent).backup_\(timestamp)_\(UUID().uuidString)")
```

- [ ] **Step 3: Fix `listBackups`' timestamp parsing**

Change:

```swift
            let tsString = String(name.dropFirst(prefix.count))
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let date = formatter.date(from: tsString) ?? Date()
```

to:

```swift
            // Only the fixed-width "yyyyMMdd_HHmmss" (15 characters) is
            // the actual timestamp — anything appended after it (the
            // uniqueness suffix) must be ignored rather than fed into
            // the strict formatter, which would otherwise fail to parse
            // and silently fall back to `Date()`.
            let tsString = String(name.dropFirst(prefix.count).prefix(15))
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let date = formatter.date(from: tsString) ?? Date()
```

- [ ] **Step 4: Add the two regression tests**

Add inside `@Suite struct SaveManagerTests { ... }`, after `makeTestSaveBuildsAValidSaveGameInfo`:

```swift
    @Test func backupSaveCreatesASiblingBackupFolderWithMatchingContent() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let save = try env.makeSave(named: "BackupMe", content: "original content")

        #expect(SaveManager.shared.backupSave(info: save))

        let backups = SaveManager.shared.listBackups(for: save)
        #expect(backups.count == 1)
        let backedUpFile = backups[0].folderPath.appendingPathComponent("BackupMe")
        let backedUpContent = try String(contentsOf: backedUpFile, encoding: .utf8)
        #expect(backedUpContent == "original content")
    }

    @Test func backupSaveCreatedBackToBackGetDistinctFolderNames() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let save = try env.makeSave(named: "SameSecondSave")

        #expect(SaveManager.shared.backupSave(info: save))
        #expect(SaveManager.shared.backupSave(info: save))

        let backups = SaveManager.shared.listBackups(for: save)
        #expect(backups.count == 2)
        #expect(backups[0].folderPath != backups[1].folderPath)
    }
```

- [ ] **Step 5: Run the tests**

Run: `./run_tests.sh`
Expected: `SaveManagerTests` suite shows 3 tests passing.

- [ ] **Step 6: Verify the main app still builds**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app` (this task changes production behavior — re-verify).

- [ ] **Step 7: Commit**

```bash
git add StarHubTH/SaveManager.swift Tests/SaveManagerTests/SaveManagerTests.swift
git commit -m "fix: prevent same-second backup-folder-name collisions in SaveManager

backupSave's and restoreBackup's pre-restore-backup destination folder
names only embedded a second-granularity timestamp, with no uniqueness
suffix — two backups created within the same wall-clock second would
collide and the second copyItem would silently fail. Adds a UUID
suffix (same pattern already used in ModConfigBackupManager and
ModInstallBackupManager) and adjusts listBackups' strict-format date
parsing to read only the fixed-width timestamp portion, ignoring the
appended suffix."
```

---

### Task 3: `listBackups` — sort order + parsing correctness

**Files:**
- Modify: `Tests/SaveManagerTests/SaveManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `writeTestSaveFile` (Task 1); the fixed naming/parsing (Task 2).

- [ ] **Step 1: Add the two tests**

```swift
    @Test func listBackupsSortsNewestFirst() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let save = try env.makeSave(named: "SortOrderSave")

        #expect(SaveManager.shared.backupSave(info: save))
        #expect(SaveManager.shared.backupSave(info: save))

        let backups = SaveManager.shared.listBackups(for: save)
        #expect(backups.count == 2)
        #expect(backups[0].timestamp >= backups[1].timestamp)
    }

    @Test func listBackupsParsesTimestampCorrectlyDespiteUniquenessSuffix() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let save = try env.makeSave(named: "ParseTestSave")

        // Manually construct a backup folder matching the exact naming
        // scheme backupSave produces, with a deliberately old, known
        // timestamp embedded — if listBackups' parsing regressed to
        // reading the whole suffix (including the UUID) instead of just
        // the first 15 characters, the strict formatter would fail to
        // parse it and silently fall back to `Date()` (today), which
        // this test would catch as a large timestamp mismatch.
        let oldTimestamp = "20200115_093000"
        let backupFolderName = "ParseTestSave.backup_\(oldTimestamp)_\(UUID().uuidString)"
        let backupFolderURL = env.savesDir.appendingPathComponent(backupFolderName, isDirectory: true)
        try writeTestSaveFile(at: backupFolderURL.appendingPathComponent("ParseTestSave"), content: "old backup")

        let referenceFormatter = DateFormatter()
        referenceFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let expectedDate = referenceFormatter.date(from: oldTimestamp)!

        let backups = SaveManager.shared.listBackups(for: save)

        #expect(backups.count == 1)
        #expect(backups[0].timestamp == expectedDate)
    }
```

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `SaveManagerTests` suite shows 5 tests passing.

- [ ] **Step 3: Commit**

```bash
git add Tests/SaveManagerTests/SaveManagerTests.swift
git commit -m "test: cover listBackups' sort order and fixed-width timestamp parsing"
```

---

### Task 4: `restoreBackup` — successful restore

**Files:**
- Modify: `Tests/SaveManagerTests/SaveManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `writeTestSaveFile` (Task 1).

- [ ] **Step 1: Add the test**

```swift
    @Test func restoreBackupBacksUpCurrentStateThenSwapsInTheBackup() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let save = try env.makeSave(named: "RestoreMe", content: "original content")
        #expect(SaveManager.shared.backupSave(info: save))
        let backups = SaveManager.shared.listBackups(for: save)
        #expect(backups.count == 1)
        let backup = backups[0]

        // Simulate further play after the backup was taken.
        try writeTestSaveFile(at: save.fileURL, content: "changed content")

        #expect(SaveManager.shared.restoreBackup(backup: backup, info: save))

        let restoredContent = try String(contentsOf: save.fileURL, encoding: .utf8)
        #expect(restoredContent == "original content")

        // restoreBackup also backs up the pre-restore ("changed") state
        // before swapping — there should now be 2 backups total.
        let allBackups = SaveManager.shared.listBackups(for: save)
        #expect(allBackups.count == 2)
    }
```

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `SaveManagerTests` suite shows 6 tests passing.

- [ ] **Step 3: Commit**

```bash
git add Tests/SaveManagerTests/SaveManagerTests.swift
git commit -m "test: cover restoreBackup's successful restore path"
```

---

### Task 5: `restoreBackup` — rollback on copy failure

**Files:**
- Modify: `Tests/SaveManagerTests/SaveManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment`, `writeTestSaveFile` (Task 1).

- [ ] **Step 1: Add the test**

```swift
    @Test func restoreBackupRollsBackOnCopyFailure() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let save = try env.makeSave(named: "RollbackMe", content: "original content")
        #expect(SaveManager.shared.backupSave(info: save))
        let backup = SaveManager.shared.listBackups(for: save)[0]

        try writeTestSaveFile(at: save.fileURL, content: "changed content")

        // Strip all permissions from the backup's own source folder so
        // the final copy-into-place step fails deterministically — after
        // the live save folder has already been moved aside, which is
        // exactly the failure window the rollback protects against.
        // (Empirically verified in an earlier plan: a 0-permission
        // source directory makes a recursive copy fail with "Permission
        // denied", without affecting operations on other, untouched
        // directories.)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: backup.folderPath.path)

        #expect(!SaveManager.shared.restoreBackup(backup: backup, info: save))

        // The rollback must have moved the live folder back into place —
        // reading it doesn't require write access to the (still locked)
        // backup source folder.
        let restoredContent = try String(contentsOf: save.fileURL, encoding: .utf8)
        #expect(restoredContent == "changed content")
    }
```

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `SaveManagerTests` suite shows 7 tests passing.

- [ ] **Step 3: Commit**

```bash
git add Tests/SaveManagerTests/SaveManagerTests.swift
git commit -m "test: regression-cover restoreBackup's copy-failure rollback"
```

---

### Task 6: `deleteSave` + `deleteBackup`

**Files:**
- Modify: `Tests/SaveManagerTests/SaveManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment` (Task 1).

- [ ] **Step 1: Add the two tests**

```swift
    @Test func deleteSaveRemovesTheSaveFolderFromItsOriginalLocation() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let save = try env.makeSave(named: "DeleteMe")
        let folderPath = save.fileURL.deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: folderPath.path))

        #expect(SaveManager.shared.deleteSave(info: save))

        #expect(!FileManager.default.fileExists(atPath: folderPath.path))
    }

    @Test func deleteBackupRemovesTheBackupFolderFromItsOriginalLocation() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let save = try env.makeSave(named: "DeleteBackupMe")
        #expect(SaveManager.shared.backupSave(info: save))
        let backup = SaveManager.shared.listBackups(for: save)[0]
        #expect(FileManager.default.fileExists(atPath: backup.folderPath.path))

        #expect(SaveManager.shared.deleteBackup(backup))

        #expect(!FileManager.default.fileExists(atPath: backup.folderPath.path))
    }
```

Note: both methods use `FileManager.trashItem` internally (move to the real system Trash, not permanent delete) — per the plan's Global Constraints, this leaves small, inert debris in the real Trash after each test run, which cannot be avoided or cleaned up without changing `deleteSave`/`deleteBackup`'s signature (out of scope here). Assertions verify the item's *original* location is empty, not the Trash destination.

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `SaveManagerTests` suite shows 9 tests passing.

- [ ] **Step 3: Commit**

```bash
git add Tests/SaveManagerTests/SaveManagerTests.swift
git commit -m "test: cover deleteSave and deleteBackup removing their original folders"
```

---

### Task 7: `duplicateSave` — clone + name-collision avoidance

**Files:**
- Modify: `Tests/SaveManagerTests/SaveManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment` (Task 1).

- [ ] **Step 1: Add the two tests**

```swift
    @Test func duplicateSaveClonesWithRenamedInternalFileAndPatchedFields() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let save = try env.makeSave(named: "DupMe", content: "<player><name>Old</name><farmName>OldFarm</farmName></player>")

        #expect(SaveManager.shared.duplicateSave(info: save, newName: "NewPlayer", newFarm: "NewFarm"))

        let clonedFolder = env.savesDir.appendingPathComponent("DupMe_copy", isDirectory: true)
        let clonedFile = clonedFolder.appendingPathComponent("DupMe_copy")
        #expect(FileManager.default.fileExists(atPath: clonedFile.path))
        // The original-named internal file should have been renamed away.
        #expect(!FileManager.default.fileExists(atPath: clonedFolder.appendingPathComponent("DupMe").path))

        let clonedContent = try String(contentsOf: clonedFile, encoding: .utf8)
        #expect(clonedContent.contains("<name>NewPlayer</name>"))
        #expect(clonedContent.contains("<farmName>NewFarm</farmName>"))
    }

    @Test func duplicateSaveCalledTwiceAvoidsNameCollision() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let save = try env.makeSave(named: "DupTwice")

        #expect(SaveManager.shared.duplicateSave(info: save, newName: "P1", newFarm: "F1"))
        #expect(SaveManager.shared.duplicateSave(info: save, newName: "P2", newFarm: "F2"))

        // cloneSaveFolder's collision counter starts at 1 and appends it
        // directly (not incrementing an implicit "_0") — the second
        // call produces "_copy_1", not "_copy_2".
        #expect(FileManager.default.fileExists(atPath: env.savesDir.appendingPathComponent("DupTwice_copy").path))
        #expect(FileManager.default.fileExists(atPath: env.savesDir.appendingPathComponent("DupTwice_copy_1").path))
    }
```

- [ ] **Step 2: Run the tests**

Run: `./run_tests.sh`
Expected: `SaveManagerTests` suite shows 11 tests passing.

- [ ] **Step 3: Commit**

```bash
git add Tests/SaveManagerTests/SaveManagerTests.swift
git commit -m "test: cover duplicateSave's clone-and-patch and name-collision avoidance"
```

---

### Task 8: `branchFromBackup`

**Files:**
- Modify: `Tests/SaveManagerTests/SaveManagerTests.swift`

**Interfaces:**
- Consumes: `TestEnvironment` (Task 1).

- [ ] **Step 1: Add the test**

```swift
    @Test func branchFromBackupClonesFromABackupFolderWithPatchedFields() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }

        let save = try env.makeSave(named: "BranchMe", content: "<player><name>Old</name><farmName>OldFarm</farmName></player>")
        #expect(SaveManager.shared.backupSave(info: save))
        let backup = SaveManager.shared.listBackups(for: save)[0]

        #expect(SaveManager.shared.branchFromBackup(backup: backup, newName: "BranchPlayer", newFarm: "BranchFarm"))

        let branchedFolder = env.savesDir.appendingPathComponent("BranchMe_branch", isDirectory: true)
        let branchedFile = branchedFolder.appendingPathComponent("BranchMe_branch")
        #expect(FileManager.default.fileExists(atPath: branchedFile.path))
        let branchedContent = try String(contentsOf: branchedFile, encoding: .utf8)
        #expect(branchedContent.contains("<name>BranchPlayer</name>"))
        #expect(branchedContent.contains("<farmName>BranchFarm</farmName>"))
    }
```

- [ ] **Step 2: Run the full suite one last time**

Run: `./run_tests.sh`
Expected: `SaveManagerTests` suite shows 12 tests passing (alongside the unaffected `ModConfigBackupManagerTests` [14] and `ModInstallBackupManagerTests` [15] — 41 total).

- [ ] **Step 3: Final full verification**

Run: `python3 build_app.py`
Expected: `[SUCCESS] Successfully built StarHubTH.app`.

- [ ] **Step 4: Commit**

```bash
git add Tests/SaveManagerTests/SaveManagerTests.swift
git commit -m "test: cover branchFromBackup's clone-and-patch path

SaveManager folder-operations extension complete: 12 tests covering
backup, restore (including a real rollback-on-failure regression
test), delete, duplicate, and branch, plus a regression fix for a
same-second backup-folder-naming collision discovered during
exploration."
```
