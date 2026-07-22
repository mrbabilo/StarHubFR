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
