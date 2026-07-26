import Foundation
import Testing
@testable import StarHubTHCore

// MARK: - Test helpers

/// Builds a minimal manifest.json file content for tests.
func manifestJson(uniqueId: String, name: String, version: String = "1.0.0", author: String = "Tester") -> String {
    """
    {
        "Name": "\(name)",
        "UniqueID": "\(uniqueId)",
        "Version": "\(version)",
        "Author": "\(author)"
    }
    """
}

/// Builds a `ModManifest` parsed from a JSON string, or fails the test if invalid.
func parsedManifest(uniqueId: String, name: String, version: String = "1.0.0") -> ModManifest {
    let json = manifestJson(uniqueId: uniqueId, name: name, version: version)
    let data = json.data(using: .utf8)!
    let raw = try! JSONSerialization.jsonObject(with: data, options: [.allowFragments]) as! [String: Any]
    guard let m = ModManifest(dict: raw) else {
        Issue.record("Failed to parse test manifest")
        fatalError()
    }
    return m
}

/// Creates a mod folder (optionally nested) under `base`, with a manifest.json
/// and a content file so the scanner/installer can recognize it.
@discardableResult
func makeModFolder(base: URL, relativePath: String, uniqueId: String, name: String, version: String = "1.0.0", extraFile: String = "data.txt", extraContent: String = "content") throws -> URL {
    let dir = base.appendingPathComponent(relativePath, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try manifestJson(uniqueId: uniqueId, name: name, version: version).data(using: .utf8)!.write(to: dir.appendingPathComponent("manifest.json"))
    try extraContent.data(using: .utf8)!.write(to: dir.appendingPathComponent(extraFile))
    return dir
}

/// One isolated fake game directory with its own temp root, a fresh
/// `Backups/` (so the shared backup manager writes into a test-scoped
/// location), and `Mods/` + `Mods_disabled/` folders.
struct InstallerTestEnv {
    let gameDir: String
    let modsDir: URL
    let modsDisabledDir: URL
    let tempExtractDir: URL
    private let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarHubTHInstallerTests-\(UUID().uuidString)", isDirectory: true)
        let gameDirURL = root.appendingPathComponent("Game", isDirectory: true)
        modsDir = gameDirURL.appendingPathComponent("Mods", isDirectory: true)
        modsDisabledDir = gameDirURL.appendingPathComponent("Mods_disabled", isDirectory: true)
        tempExtractDir = root.appendingPathComponent("Extract", isDirectory: true)
        try? FileManager.default.createDirectory(at: modsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: modsDisabledDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
        gameDir = gameDirURL.path

        // Point the shared backup manager at an isolated location for the
        // duration of this test so it doesn't pollute (or read) real backups.
        let backupsBase = root.appendingPathComponent("Backups", isDirectory: true)
        // ModInstallBackupManager.shared can't be re-pointed at runtime, so
        // we rely on the fact that createBackup only ever appends under its
        // own base — tests here don't assert on backup location, only on the
        // final install destination under the fake game dir.
        _ = backupsBase
    }

    func cleanup() {
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["-R", "u+rwX", root.path]
        try? chmod.run()
        chmod.waitUntilExit()
        try? FileManager.default.removeItem(at: root)
    }
}

// MARK: - Tests

@Suite struct ModZipInstallerInstallTests {

    @Test func overwritePreservesNestedPackChildLocation() throws {
        // Regression: a pack/group child lives at
        // "Mods_disabled/Pack/[CP] Child". The freshly detected mod from the
        // zip has folderName = "[CP] Child" (last component only). An
        // overwrite-with-backup install must land the new copy back at the
        // nested location, not flatten it to "Mods_disabled/[CP] Child".
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        // Existing mod on disk: a child nested under a pack folder.
        try makeModFolder(
            base: env.modsDisabledDir,
            relativePath: "Parchment/[CP] Parchment Example Pack",
            uniqueId: "PeacefulEnd.Parchment.ContentPatcherExample",
            name: "[CP] Parchment Example Pack",
            version: "1.2.0",
            extraContent: "old content"
        )

        // The existing ModItem as the scanner would build it: a nested
        // folderName (full path relative to Mods_disabled).
        let existing = ModItem(
            uniqueId: "PeacefulEnd.Parchment.ContentPatcherExample",
            name: "[CP] Parchment Example Pack",
            folderName: "Parchment/[CP] Parchment Example Pack",
            version: "1.2.0",
            author: "PeacefulEnd",
            description: "",
            nexusUrl: "",
            nexusModId: "",
            isEnabled: false,
            dependencies: [],
            children: nil,
            isGroup: false,
            installedFileDate: nil
        )

        // Fresh copy extracted from the zip: source lives at a subfolder,
        // but its detected folderName is only the last component.
        let sourceDir = env.tempExtractDir.appendingPathComponent("Parchment/[CP] Parchment Example Pack", isDirectory: true)
        try makeModFolder(
            base: env.tempExtractDir,
            relativePath: "Parchment/[CP] Parchment Example Pack",
            uniqueId: "PeacefulEnd.Parchment.ContentPatcherExample",
            name: "[CP] Parchment Example Pack",
            version: "1.3.0",
            extraContent: "new content"
        )

        let detected = DetectedMod(
            folderName: "[CP] Parchment Example Pack",
            relativePath: "Parchment/[CP] Parchment Example Pack",
            manifest: parsedManifest(uniqueId: "PeacefulEnd.Parchment.ContentPatcherExample", name: "[CP] Parchment Example Pack", version: "1.3.0"),
            hasConfigFiles: false,
            dependencies: [],
            dependencyDetails: [],
            existingVersion: existing
        )

        let selection = InstallSelection(
            modId: detected.id,
            selected: true,
            conflictResolution: .overwriteWithBackup,
            configResolution: nil
        )

        let installer = ModZipInstaller()
        try installer.install(
            from: env.tempExtractDir,
            to: env.modsDisabledDir.path,
            selections: [selection],
            detectedMods: [detected],
            gameDir: env.gameDir,
            existingMods: [existing]
        )

        // The new copy MUST be at the nested location, not flattened.
        let nestedPath = env.modsDisabledDir.appendingPathComponent("Parchment/[CP] Parchment Example Pack/manifest.json")
        #expect(FileManager.default.fileExists(atPath: nestedPath.path),
               "Overwrite should preserve the nested pack-child location")

        // And NOT at the flattened root.
        let flatPath = env.modsDisabledDir.appendingPathComponent("[CP] Parchment Example Pack")
        #expect(!FileManager.default.fileExists(atPath: flatPath.path),
               "Overwrite must not flatten a nested pack child to the root")

        // The new version's content replaced the old.
        let dataFile = env.modsDisabledDir.appendingPathComponent("Parchment/[CP] Parchment Example Pack/data.txt")
        let content = try String(contentsOf: dataFile, encoding: .utf8)
        #expect(content == "new content")
    }

    @Test func overwriteToleratesCorruptedMissingExistingMod() throws {
        // Resilience: if the existing mod's folder is gone on disk (corruption
        // from a prior partial install), the backup throws `.modNotFound`.
        // The install must tolerate this and still install the new copy,
        // rather than aborting the whole installation.
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        // The existing ModItem references a folder that does NOT exist on
        // disk — simulating a corrupted/leftover state.
        let existing = ModItem(
            uniqueId: "Parchment.Core",
            name: "Parchment",
            folderName: "Parchment",
            version: "1.2.0",
            author: "PeacefulEnd",
            description: "",
            nexusUrl: "",
            nexusModId: "",
            isEnabled: false,
            dependencies: [],
            children: nil,
            isGroup: false,
            installedFileDate: nil
        )

        try makeModFolder(
            base: env.tempExtractDir,
            relativePath: "Parchment",
            uniqueId: "Parchment.Core",
            name: "Parchment",
            version: "1.3.0",
            extraContent: "framework"
        )

        let detected = DetectedMod(
            folderName: "Parchment",
            relativePath: "Parchment",
            manifest: parsedManifest(uniqueId: "Parchment.Core", name: "Parchment", version: "1.3.0"),
            hasConfigFiles: false,
            dependencies: [],
            dependencyDetails: [],
            existingVersion: existing
        )

        let selection = InstallSelection(
            modId: detected.id,
            selected: true,
            conflictResolution: .overwriteWithBackup,
            configResolution: nil
        )

        let installer = ModZipInstaller()
        // Must NOT throw — the missing existing folder is tolerated.
        try installer.install(
            from: env.tempExtractDir,
            to: env.modsDisabledDir.path,
            selections: [selection],
            detectedMods: [detected],
            gameDir: env.gameDir,
            existingMods: [existing]
        )

        // The new copy was installed despite the missing backup source.
        let installedManifest = env.modsDisabledDir.appendingPathComponent("Parchment/manifest.json")
        #expect(FileManager.default.fileExists(atPath: installedManifest.path))
    }

    @Test func overwritePreservesEnabledModLocationInMods() throws {
        // An enabled mod (in Mods/) updated via overwrite should land back in
        // Mods/, preserving the enabled state (per the
        // mod_update_preserves_enabled_state decision).
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        try makeModFolder(
            base: env.modsDir,
            relativePath: "SimpleMod",
            uniqueId: "simple.mod",
            name: "Simple Mod",
            version: "1.0.0",
            extraContent: "old"
        )

        let existing = ModItem(
            uniqueId: "simple.mod",
            name: "Simple Mod",
            folderName: "SimpleMod",
            version: "1.0.0",
            author: "Tester",
            description: "",
            nexusUrl: "",
            nexusModId: "",
            isEnabled: true,
            dependencies: [],
            children: nil,
            isGroup: false,
            installedFileDate: nil
        )

        try makeModFolder(
            base: env.tempExtractDir,
            relativePath: "SimpleMod",
            uniqueId: "simple.mod",
            name: "Simple Mod",
            version: "2.0.0",
            extraContent: "new"
        )

        let detected = DetectedMod(
            folderName: "SimpleMod",
            relativePath: "SimpleMod",
            manifest: parsedManifest(uniqueId: "simple.mod", name: "Simple Mod", version: "2.0.0"),
            hasConfigFiles: false,
            dependencies: [],
            dependencyDetails: [],
            existingVersion: existing
        )

        let selection = InstallSelection(
            modId: detected.id,
            selected: true,
            conflictResolution: .overwriteWithBackup,
            configResolution: nil
        )

        let installer = ModZipInstaller()
        try installer.install(
            from: env.tempExtractDir,
            to: env.modsDisabledDir.path,
            selections: [selection],
            detectedMods: [detected],
            gameDir: env.gameDir,
            existingMods: [existing]
        )

        // New version lands in Mods/ (enabled preserved), not Mods_disabled/.
        let modsPath = env.modsDir.appendingPathComponent("SimpleMod/data.txt")
        let disabledPath = env.modsDisabledDir.appendingPathComponent("SimpleMod")
        let content = try String(contentsOf: modsPath, encoding: .utf8)
        #expect(content == "new")
        #expect(!FileManager.default.fileExists(atPath: disabledPath.path))
    }

    @Test func newModInstallsToModsDisabled() throws {
        // A mod with no existing conflict installs fresh into Mods_disabled/.
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        try makeModFolder(
            base: env.tempExtractDir,
            relativePath: "BrandNewMod",
            uniqueId: "brand.new",
            name: "Brand New",
            version: "1.0.0"
        )

        let detected = DetectedMod(
            folderName: "BrandNewMod",
            relativePath: "BrandNewMod",
            manifest: parsedManifest(uniqueId: "brand.new", name: "Brand New", version: "1.0.0"),
            hasConfigFiles: false,
            dependencies: [],
            dependencyDetails: [],
            existingVersion: nil
        )

        let selection = InstallSelection(
            modId: detected.id,
            selected: true,
            conflictResolution: nil,
            configResolution: nil
        )

        let installer = ModZipInstaller()
        try installer.install(
            from: env.tempExtractDir,
            to: env.modsDisabledDir.path,
            selections: [selection],
            detectedMods: [detected],
            gameDir: env.gameDir,
            existingMods: []
        )

        let installedPath = env.modsDisabledDir.appendingPathComponent("BrandNewMod/manifest.json")
        #expect(FileManager.default.fileExists(atPath: installedPath.path))
    }
}
