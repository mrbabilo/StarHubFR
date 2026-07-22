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
}
