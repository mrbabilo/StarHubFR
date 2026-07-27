import Foundation
import Testing
@testable import StarHubTHCore

// MARK: - Test helpers

/// Creates a minimal manifest.json inside `dir`.
func writeManifest(in dir: URL, uniqueId: String, name: String = "Test", version: String = "1.0.0") throws {
    let json = """
    {"Name":"\(name)","UniqueID":"\(uniqueId)","Version":"\(version)","Author":"T"}
    """
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try json.data(using: .utf8)!.write(to: dir.appendingPathComponent("manifest.json"))
}

/// Creates a fake text file at `dir/filename`.
func writeFile(in dir: URL, filename: String, content: String = "x") throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try content.data(using: .utf8)!.write(to: dir.appendingPathComponent(filename))
}

/// One isolated fake game directory for repairer tests.
struct RepairerTestEnv {
    let gameDir: String
    let modsDir: URL
    let modsDisabledDir: URL
    private let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarHubRepairerTests-\(UUID().uuidString)", isDirectory: true)
        let gameDirURL = root.appendingPathComponent("Game", isDirectory: true)
        modsDir = gameDirURL.appendingPathComponent("Mods", isDirectory: true)
        modsDisabledDir = gameDirURL.appendingPathComponent("Mods_disabled", isDirectory: true)
        try? FileManager.default.createDirectory(at: modsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: modsDisabledDir, withIntermediateDirectories: true)
        gameDir = gameDirURL.path
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    /// All `_Trash_*` folders created under the game dir.
    func trashFolders() -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: gameDir) else { return [] }
        return entries
            .filter { $0.hasPrefix("_Trash_") }
            .map { URL(fileURLWithPath: gameDir).appendingPathComponent($0) }
    }
}

// MARK: - Tests

@Suite struct ModFolderRepairerTests {

    @Test func doesNotAutoQuarantineOrphanFolder() throws {
        // Orphan folders (no manifest) are ambiguous — a legitimate user
        // asset folder could match. They are NOT auto-quarantined; the scan
        // simply ignores them and the user reviews manually.
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        let validMod = env.modsDir.appendingPathComponent("RealMod")
        try writeManifest(in: validMod, uniqueId: "real.mod")

        let orphan = env.modsDir.appendingPathComponent("BrokenLeftover")
        try writeFile(in: orphan, filename: "junk.txt", content: "residue")

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.quarantined.isEmpty)
        // Valid mod untouched.
        #expect(FileManager.default.fileExists(atPath: validMod.appendingPathComponent("manifest.json").path))
        // Orphan left in place (not auto-quarantined).
        #expect(FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test func quarantinesEmptyTopLevelFolder() throws {
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        // The repairer only scans Mods/ now (disabled mods live there as .X).
        let empty = env.modsDir.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.quarantined.contains { $0.kind == .emptyFolder })
        #expect(!FileManager.default.fileExists(atPath: empty.path))
    }

    @Test func quarantinesDSStoreFile() throws {
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        // .DS_Store directly at the root of Mods/.
        try writeFile(in: env.modsDir, filename: ".DS_Store")

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.quarantined.contains { $0.kind == .osJunkFile })
        #expect(!FileManager.default.fileExists(atPath: env.modsDir.appendingPathComponent(".DS_Store").path))
    }

    @Test func sweepsJunkDeepInsideValidMod() throws {
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        let mod = env.modsDir.appendingPathComponent("GoodMod")
        try writeManifest(in: mod, uniqueId: "good.mod")
        // OS junk nested inside the mod's assets folder.
        try writeFile(in: mod.appendingPathComponent("assets"), filename: ".DS_Store")

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        // The mod itself is untouched (manifest still there).
        #expect(FileManager.default.fileExists(atPath: mod.appendingPathComponent("manifest.json").path))
        // The nested .DS_Store was swept to trash.
        let dsStore = mod.appendingPathComponent("assets/.DS_Store")
        #expect(!FileManager.default.fileExists(atPath: dsStore.path))
        #expect(report.quarantined.contains { $0.kind == .osJunkFile })
    }

    @Test func quarantinesMacOSXFolder() throws {
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        let macosx = env.modsDir.appendingPathComponent("__MACOSX")
        try writeFile(in: macosx.appendingPathComponent("subfolder"), filename: "placeholder.txt")

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.quarantined.contains { $0.kind == .osJunkFolder })
        #expect(!FileManager.default.fileExists(atPath: macosx.path))
    }

    @Test func doesNotAutoQuarantineNestedModsWrapper() throws {
        // Nested Mods/Mods wrappers are ambiguous — some mods legitimately
        // bundle reference Mods dirs. NOT auto-quarantined; left for manual review.
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        let wrapper = env.modsDir.appendingPathComponent("WrapperMod")
        let nestedMods = wrapper.appendingPathComponent("Mods")
        try writeManifest(in: nestedMods.appendingPathComponent("InnerMod"), uniqueId: "inner.mod")

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.quarantined.isEmpty)
        // Wrapper left in place.
        #expect(FileManager.default.fileExists(atPath: wrapper.path))
    }

    @Test func doesNotTouchValidPackFolder() throws {
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        // A pack: top-level folder with multiple child mods, no manifest at
        // its own root — must NOT be quarantined.
        let pack = env.modsDir.appendingPathComponent("MyPack")
        try writeManifest(in: pack.appendingPathComponent("ChildA"), uniqueId: "a.mod")
        try writeManifest(in: pack.appendingPathComponent("ChildB"), uniqueId: "b.mod")

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.quarantined.isEmpty)
        #expect(FileManager.default.fileExists(atPath: pack.appendingPathComponent("ChildA/manifest.json").path))
    }

    @Test func detectsDuplicatesAcrossEnabledAndDisabled() throws {
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        // Same UniqueID in both an enabled (Mods/DupMod) and a disabled
        // (Mods/.DupMod_Copy) folder under Mods/.
        try writeManifest(in: env.modsDir.appendingPathComponent("DupMod"), uniqueId: "dup.mod")
        try writeManifest(in: env.modsDir.appendingPathComponent(".DupMod_Copy"), uniqueId: "dup.mod")

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.duplicates.count == 1)
        #expect(report.duplicates[0].uniqueId == "dup.mod")
        // Duplicates are NOT auto-resolved — both copies stay on disk.
        #expect(FileManager.default.fileExists(atPath: env.modsDir.appendingPathComponent("DupMod/manifest.json").path))
        #expect(FileManager.default.fileExists(atPath: env.modsDir.appendingPathComponent(".DupMod_Copy/manifest.json").path))
    }

    @Test func cleanFolderProducesEmptyReport() throws {
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        try writeManifest(in: env.modsDir.appendingPathComponent("CleanMod"), uniqueId: "clean.mod")

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.isEmpty)
        #expect(report.trashPath == nil)
    }

    @Test func idempotentRunDoesNotReprocessTrash() throws {
        let env = RepairerTestEnv()
        defer { env.cleanup() }

        // Use OS junk (auto-quarantined) — a .DS_Store inside an otherwise
        // empty top-level folder. The folder becomes empty after the sweep
        // and is then quarantined too on the first run.
        let folder = env.modsDir.appendingPathComponent("WithJunk")
        try writeFile(in: folder, filename: ".DS_Store")

        let r1 = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)
        #expect(!r1.quarantined.isEmpty)

        // Second run: the trash folder itself must not be re-scanned or
        // double-quarantined, and no new items should be found.
        let r2 = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)
        #expect(r2.quarantined.isEmpty)
    }
}
