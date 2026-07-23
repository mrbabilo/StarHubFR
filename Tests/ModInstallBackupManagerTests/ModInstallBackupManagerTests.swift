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
}
