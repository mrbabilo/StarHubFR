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
