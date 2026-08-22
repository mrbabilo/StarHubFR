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
/// location), and a `Mods/` folder. `Mods_disabled/` is still created for
/// source compatibility with the installer's `to:` param, but disabled
/// mods now live under `Mods/` as `.X`.
struct InstallerTestEnv {
    let gameDir: String
    let modsDir: URL
    let modsDisabledDir: URL
    let tempExtractDir: URL
    /// Le magasin de sauvegardes **du test**. Sans lui, chaque exécution
    /// déposait une sauvegarde dans les vraies données de l'utilisateur :
    /// 1 148 des 1 494 entrées de son index venaient d'ici, mesuré le
    /// 2026-08-21.
    let backupManager: ModInstallBackupManager
    /// Là où ce magasin écrit — ce que le test vérifie.
    let backupsRoot: URL
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

        // Un magasin de sauvegardes à soi, sous le dossier temporaire du
        // test. L'installateur le reçoit à la construction : ce qui suivait
        // ici auparavant ne faisait que **constater** que le magasin partagé
        // n'était pas repointable, et laissait donc écrire dans le vrai.
        backupsRoot = root.appendingPathComponent("Backups", isDirectory: true)
        backupManager = ModInstallBackupManager(backupsBasePath: backupsRoot)
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
        // "Mods/.Parchment/[CP] Child" (disabled = dot prefix at the
        // top-level entry). The freshly detected mod from the zip has
        // folderName = "[CP] Child" (last component only). An
        // overwrite-with-backup install must land the new copy back at the
        // nested location, not flatten it to "Mods/.[CP] Child".
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        // Existing mod on disk: a child nested under a disabled pack folder
        // (the dot prefix marks the whole tree as disabled).
        try makeModFolder(
            base: env.modsDir,
            relativePath: ".Parchment/[CP] Parchment Example Pack",
            uniqueId: "PeacefulEnd.Parchment.ContentPatcherExample",
            name: "[CP] Parchment Example Pack",
            version: "1.2.0",
            extraContent: "old content"
        )

        // The existing ModItem as the scanner would build it: a nested
        // folderName (logical, no dot — the scanner strips the prefix when
        // computing folderName).
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

        let installer = ModZipInstaller(backupManager: env.backupManager)
        try installer.install(
            from: env.tempExtractDir,
            to: env.modsDisabledDir.path,
            selections: [selection],
            detectedMods: [detected],
            gameDir: env.gameDir,
            existingMods: [existing]
        )

        // La sauvegarde de l'écrasement va **là où on l'a dit**, et nulle part
        // ailleurs. Le magasin n'était pas injectable : ce test écrivait pour
        // de bon dans `Application Support`, à chaque exécution.
        let backups = env.backupManager.loadBackups()
        #expect(backups.count == 1)
        #expect(backups.first?.backupPath.hasPrefix(env.backupsRoot.path) == true)

        // The new copy MUST be at the nested location under Mods/.Parchment/
        // (disabled, since the existing mod was disabled), not flattened.
        let nestedPath = env.modsDir.appendingPathComponent(".Parchment/[CP] Parchment Example Pack/manifest.json")
        #expect(FileManager.default.fileExists(atPath: nestedPath.path),
               "Overwrite should preserve the nested pack-child location")

        // And NOT at the flattened root.
        let flatPath = env.modsDir.appendingPathComponent(".[CP] Parchment Example Pack")
        #expect(!FileManager.default.fileExists(atPath: flatPath.path),
               "Overwrite must not flatten a nested pack child to the root")

        // The new version's content replaced the old.
        let dataFile = env.modsDir.appendingPathComponent(".Parchment/[CP] Parchment Example Pack/data.txt")
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

        let installer = ModZipInstaller(backupManager: env.backupManager)
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
        // The existing mod was disabled, so the new copy lands disabled too
        // (Mods/.Parchment).
        let installedManifest = env.modsDir.appendingPathComponent(".Parchment/manifest.json")
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

        let installer = ModZipInstaller(backupManager: env.backupManager)
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

    /// La rétention tourne **à l'installation**, pas seulement quand on ouvre
    /// la page des sauvegardes. Qui n'y allait jamais ne l'exécutait jamais,
    /// et l'historique grossissait sans limite.
    @Test func installingRunsTheRetentionSweep() throws {
        let env = InstallerTestEnv()
        defer { env.cleanup() }

        // Huit vieilles sauvegardes du **même mois**, il y a cent jours : la
        // politique en protège les cinq plus récentes et la première du mois,
        // donc il y a bien de quoi élaguer. Un chemin inexistant suffit —
        // la purge sait qu'un dossier disparu n'est plus à supprimer.
        let old = Date().addingTimeInterval(-100 * 24 * 3600)
        env.backupManager.seedIndexForTesting(with: (0..<8).map { index in
            ModInstallBackup(
                timestamp: old.addingTimeInterval(Double(index) * 3600),
                originalFolderName: "AncientMod",
                backupPath: "/nonexistent/AncientMod-\(index)",
                modMetadata: ModMetadata(name: "Ancient", version: "1.0.0",
                                         author: "Tester", uniqueId: "ancient.mod"),
                reason: .beforeUpdate)
        })
        #expect(env.backupManager.loadBackups().count == 8)

        try makeModFolder(base: env.modsDir, relativePath: "SimpleMod",
                          uniqueId: "simple.mod", name: "Simple Mod",
                          version: "1.0.0", extraContent: "old")
        let existing = ModItem(
            uniqueId: "simple.mod", name: "Simple Mod", folderName: "SimpleMod",
            version: "1.0.0", author: "Tester", description: "", nexusUrl: "",
            nexusModId: "", isEnabled: true, dependencies: [], children: nil,
            isGroup: false, installedFileDate: nil)
        try makeModFolder(base: env.tempExtractDir, relativePath: "SimpleMod",
                          uniqueId: "simple.mod", name: "Simple Mod",
                          version: "2.0.0", extraContent: "new")
        let detected = DetectedMod(
            folderName: "SimpleMod", relativePath: "SimpleMod",
            manifest: parsedManifest(uniqueId: "simple.mod", name: "Simple Mod", version: "2.0.0"),
            hasConfigFiles: false, dependencies: [], dependencyDetails: [],
            existingVersion: existing)
        let selection = InstallSelection(modId: detected.id, selected: true,
                                         conflictResolution: .overwriteWithBackup,
                                         configResolution: nil)

        let installer = ModZipInstaller(backupManager: env.backupManager)
        try installer.install(
            from: env.tempExtractDir, to: env.modsDisabledDir.path,
            selections: [selection], detectedMods: [detected],
            gameDir: env.gameDir, existingMods: [existing])

        let remaining = env.backupManager.loadBackups()
        // La sauvegarde de cet écrasement est là, et de vieilles ont sauté.
        #expect(remaining.contains { $0.originalFolderName == "SimpleMod" })
        #expect(remaining.filter { $0.originalFolderName == "AncientMod" }.count < 8)
    }

    @Test func newModInstallsDisabledUnderMods() throws {
        // A mod with no existing conflict installs fresh as a disabled mod
        // (Mods/.BrandNewMod) — the user toggles it on explicitly.
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

        let installer = ModZipInstaller(backupManager: env.backupManager)
        try installer.install(
            from: env.tempExtractDir,
            to: env.modsDisabledDir.path,
            selections: [selection],
            detectedMods: [detected],
            gameDir: env.gameDir,
            existingMods: []
        )

        // Lands disabled under Mods/ (dot prefix), not as an enabled entry.
        let installedPath = env.modsDir.appendingPathComponent(".BrandNewMod/manifest.json")
        #expect(FileManager.default.fileExists(atPath: installedPath.path))
    }
}

// MARK: - Structure detection (pack grouping)

@Suite struct ModZipInstallerStructureTests {

    /// Fresh temp dir laid out by hand — no real archive needed.
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarHubTHStructTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func packWithSharedParentInstallsNestedUnderIt() throws {
        // A genuine multi-component pack: every component lives under one
        // shared top-level folder ("Lilybrook"). Detection must keep that
        // parent so each component's dest folderName is nested under it —
        // the mod-list scanner then groups them into a single pack entry.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try makeModFolder(base: dir, relativePath: "Lilybrook/[CC] Lilybrook",
                          uniqueId: "8BitAlien.Lilybrook.CC", name: "[CC] Lilybrook")
        try makeModFolder(base: dir, relativePath: "Lilybrook/[CP] Lilybrook",
                          uniqueId: "8BitAlien.Lilybrook", name: "Lilybrook")
        try makeModFolder(base: dir, relativePath: "Lilybrook/[FTM] Lilybrook",
                          uniqueId: "8BitAlien.Lilybrook.FTM", name: "[FTM] Lilybrook")

        let info = ModZipInstaller().analyzeExtractedDir(at: dir, zipName: "Lilybrook.zip", existingMods: [])

        #expect(info.detectedMods.count == 3)
        #expect(Set(info.detectedMods.map { $0.folderName }) ==
               ["Lilybrook/[CC] Lilybrook", "Lilybrook/[CP] Lilybrook", "Lilybrook/[FTM] Lilybrook"],
               "Pack components must install nested under the shared parent, not flattened to top level")
    }

    @Test func flatCollectionInstallsAtTopLevel() throws {
        // No shared parent: components sit at the zip root. Behavior is
        // unchanged — each lands as its own top-level folder (no synthesized
        // pack name).
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try makeModFolder(base: dir, relativePath: "[C1]", uniqueId: "mod.one", name: "One")
        try makeModFolder(base: dir, relativePath: "[C2]", uniqueId: "mod.two", name: "Two")

        let info = ModZipInstaller().analyzeExtractedDir(at: dir, zipName: "coll.zip", existingMods: [])

        #expect(info.detectedMods.count == 2)
        #expect(Set(info.detectedMods.map { $0.folderName }) == ["[C1]", "[C2]"])
    }

    @Test func bundledLibraryIsNotSplitOut() throws {
        // A mod that bundles a dependency in a nested folder (its own
        // manifest) must NOT have that dependency yanked to a separate
        // top-level install folder.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try makeModFolder(base: dir, relativePath: "MyMod", uniqueId: "my.mod", name: "My Mod")
        try makeModFolder(base: dir, relativePath: "MyMod/lib/SomeDep", uniqueId: "some.dep", name: "Some Dep")

        let info = ModZipInstaller().analyzeExtractedDir(at: dir, zipName: "MyMod.zip", existingMods: [])

        #expect(info.detectedMods.count == 1, "Bundled library must not be split into its own mod")
        #expect(info.detectedMods.first?.folderName == "MyMod")
    }

    @Test func redundantSingleWrapperStaysSingleMod() throws {
        // Regression: a single mod double-wrapped ("Pack/Pack/manifest.json")
        // is singleMod (one manifest folder), unaffected by the pack filter
        // and the shared-parent logic.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try makeModFolder(base: dir, relativePath: "Pack/Pack", uniqueId: "pack.mod", name: "Pack")

        let info = ModZipInstaller().analyzeExtractedDir(at: dir, zipName: "Pack.zip", existingMods: [])

        #expect(info.detectedMods.count == 1)
        #expect(info.detectedMods.first?.folderName == "Pack/Pack")
    }

    @Test func warningExitStatusIsNotAnExtractionFailure() {
        // Regression: a mod archive packaged on Windows uses backslashes as
        // path separators. `unzip` converts them, extracts every file, and
        // exits 1 with a warning — which we used to treat as a failure,
        // rejecting the majority of what Nexus serves. Info-ZIP, `unrar` and
        // `7z` all agree: 0 = clean, 1 = warnings, >= 2 = real error.
        #expect(ModZipInstaller.isTolerableExitStatus(0))
        #expect(ModZipInstaller.isTolerableExitStatus(1))
        #expect(!ModZipInstaller.isTolerableExitStatus(2))
        #expect(!ModZipInstaller.isTolerableExitStatus(9))
    }

    @Test func readOnlyFolderFromAnArchiveCanStillBeDeleted() throws {
        // Régression : `unzip`/`unrar` restituent les permissions stockées dans
        // l'archive. Deux mods installés livraient leurs dossiers en r-xr-xr-x,
        // et comme supprimer le contenu d'un dossier exige le droit d'écriture
        // *sur ce dossier*, l'app ne pouvait plus supprimer ce qu'elle venait
        // d'écrire : la mise à jour échouait sur « vous ne disposez pas de
        // l'autorisation nécessaire », sans issue depuis l'interface.
        let fm = FileManager.default
        let root = try makeTempDir()
        defer {
            ModZipInstaller.grantOwnerWriteAccess(in: root)
            try? fm.removeItem(at: root)
        }

        let mod = root.appendingPathComponent("[CP] Read Only")
        let assets = mod.appendingPathComponent("assets")
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        try "{}".write(to: mod.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "x".write(to: assets.appendingPathComponent("a.png"), atomically: true, encoding: .utf8)
        // Ce que l'archive impose : dossiers en lecture seule, du plus profond
        // au plus haut (sinon on ne peut plus descendre pour modifier).
        for dir in [assets, mod] {
            try fm.setAttributes([.posixPermissions: NSNumber(value: UInt16(0o555))], ofItemAtPath: dir.path)
        }

        #expect(throws: (any Error).self) { try fm.removeItem(atPath: mod.path) }
        try ModZipInstaller.removeItemGrantingWriteAccess(atPath: mod.path)
        #expect(!fm.fileExists(atPath: mod.path))
    }

    @Test func grantingWriteAccessLeavesOtherPermissionBitsAlone() {
        // On ajoute le droit d'écriture, on ne réécrit pas le mode entier :
        // un dossier déjà correct ne doit pas voir ses bits de groupe changer.
        let fm = FileManager.default
        guard let root = try? makeTempDir() else { Issue.record("temp dir"); return }
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("f.txt")
        try? "x".write(to: file, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: NSNumber(value: UInt16(0o644))], ofItemAtPath: file.path)

        ModZipInstaller.grantOwnerWriteAccess(in: root)

        let mode = (try? fm.attributesOfItem(atPath: file.path))?[.posixPermissions] as? NSNumber
        #expect(mode?.uint16Value == 0o644)
    }

    /// Écrit un fichier commençant par `signature`, pour éprouver le contrôle de
    /// format sans dépendre d'un outil de compression installé.
    private func makeArchive(named name: String, signature: [UInt8]) throws -> URL {
        let dir = try makeTempDir()
        let url = dir.appendingPathComponent(name)
        try Data(signature + [0x00, 0x00]).write(to: url)
        return url
    }

    @Test func sevenZipArchivesAreAccepted() throws {
        // Le .7z est courant sur Nexus. Avant, toute extension inconnue était
        // rejetée comme « archive corrompue » : l'utilisateur cherchait un
        // problème de fichier alors que le format n'était simplement pas géré.
        let url = try makeArchive(named: "mod.7z", signature: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        guard case .valid = ModZipInstaller().validateZip(at: url) else {
            Issue.record("un .7z valide doit être accepté"); return
        }
    }

    @Test func anUnsupportedExtensionSaysSoInsteadOfClaimingCorruption() throws {
        let url = try makeArchive(named: "mod.tar.gz", signature: [0x1F, 0x8B, 0x08, 0x00])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        guard case .unsupportedFormat(let ext) = ModZipInstaller().validateZip(at: url) else {
            Issue.record("attendu unsupportedFormat"); return
        }
        #expect(ext == "gz")
    }

    @Test func aSevenZipWithTheWrongSignatureIsStillCorrupt() throws {
        // Le contrôle de signature reste : une extension seule ne prouve rien.
        let url = try makeArchive(named: "fake.7z", signature: [0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        guard case .corrupted = ModZipInstaller().validateZip(at: url) else {
            Issue.record("attendu corrupted"); return
        }
    }

    @Test func aMislabeledArchiveIsAcceptedByItsSignature() throws {
        // Un fichier nommé `.zip` mais dont le contenu est un vrai `.7z` :
        // l'extension ment, la signature non. Le chemin Nexus le gérait déjà
        // (renommage du temporaire d'après les octets) ; le drag-drop passait
        // l'URL brute à `validateZip`, qui déclarait le format d'après
        // l'extension et rejetait l'archive saine comme « corrompue ».
        let url = try makeArchive(named: "mymod.zip", signature: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        guard case .valid = ModZipInstaller().validateZip(at: url) else {
            Issue.record("une archive saine mais mal nommée doit être lue par sa signature"); return
        }
    }

    @Test func sevenZipExtractionToolNeverUsesUnrar() {
        // unrar ne lit pas le 7z : le proposer produirait un échec obscur.
        if let tool = ModZipInstaller.find7zTool() {
            #expect(!tool.path.hasSuffix("/unrar"))
        }
    }

    @Test func archiveFormatIsReadFromTheBytesNotTheName() {
        // Le téléchargement gratuit de Nexus ne porte pas toujours d'extension
        // exploitable dans son URL : le format doit venir du fichier lui-même,
        // sinon un .7z est enregistré en .zip et part chez unzip.
        #expect(ModZipInstaller.archiveExtension(forSignature: [0x50, 0x4B, 0x03, 0x04]) == "zip")
        #expect(ModZipInstaller.archiveExtension(forSignature: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]) == "rar")
        #expect(ModZipInstaller.archiveExtension(forSignature: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) == "7z")
        // Ni un format inconnu ni un fichier trop court ne doivent inventer.
        #expect(ModZipInstaller.archiveExtension(forSignature: [0x1F, 0x8B, 0x08, 0x00]) == nil)
        #expect(ModZipInstaller.archiveExtension(forSignature: [0x37, 0x7A]) == nil)
    }

    @Test func detectionReadsARealFileOnDisk() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Nom volontairement trompeur : c'est le contenu qui doit décider.
        let url = dir.appendingPathComponent("telechargement-sans-extension")
        try Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x04]).write(to: url)
        #expect(ModZipInstaller.detectedArchiveExtension(at: url) == "7z")
    }

    @Test func sevenZipListingTotalSizeSumsEachFile() {
        // `7zz l -slt` décrit chaque entrée en lignes clé-valeur ; la taille non
        // compressée d'un fichier est sa ligne `Size = <octets>`. Le total est
        // ce que la garde anti-zip-bomb compare au plafond, pour les formats que
        // `unzip -l` ne sait pas lister (7z, et rar via 7zz).
        let listing = """
        Path = probe.7z
        Type = 7z
        Physical Size = 287
        Headers Size = 161

        Path = a.bin
        Size = 100000
        Packed Size = 126

        Path = b.bin
        Size = 250000
        Packed Size =
        """
        #expect(ModZipInstaller.totalSizeFromSevenZipListing(listing) == 350000)
        // Les en-têtes `Physical Size` / `Headers Size` ne sont pas des `Size =`
        // nus : ils ne doivent pas gonfler le total. Aucune entrée → nil
        // (fail-open, cohérent avec `unzip -l`).
        #expect(ModZipInstaller.totalSizeFromSevenZipListing("Physical Size = 287\nHeaders Size = 161\n") == nil)
        #expect(ModZipInstaller.totalSizeFromSevenZipListing("n'importe quoi") == nil)
    }

    @Test func folderNameDropsWhicheverArchiveExtensionItHas() {
        // Une archive sans dossier englobant donne son nom au dossier installé.
        // Ne retirer que « .zip » produisait « MonMod.7z » sous Mods/.
        #expect(ModZipInstaller.strippingArchiveExtension(from: "MonMod.zip") == "MonMod")
        #expect(ModZipInstaller.strippingArchiveExtension(from: "MonMod.7z") == "MonMod")
        #expect(ModZipInstaller.strippingArchiveExtension(from: "MonMod.RAR") == "MonMod")
        // Un nom sans extension d'archive reste intact, points compris.
        #expect(ModZipInstaller.strippingArchiveExtension(from: "Mon.Mod v1.2") == "Mon.Mod v1.2")
    }

    @Test func toolSearchCoversTheUsualInstallLocations() {
        // Une application lancée depuis le Finder n'hérite pas du PATH du
        // shell : la liste doit être explicite, sinon l'extraction échoue chez
        // quelqu'un qui a pourtant l'outil.
        let paths = ModZipInstaller.toolSearchPaths
        for expected in ["/opt/homebrew/bin",   // Homebrew Apple Silicon
                         "/usr/local/bin",      // Homebrew Intel
                         "/opt/local/bin",      // MacPorts
                         "/usr/bin"] {
            #expect(paths.contains(expected), "chemin manquant : \(expected)")
        }
        #expect(paths.contains { $0.hasSuffix("/.nix-profile/bin") })   // Nix
        #expect(Set(paths).count == paths.count)                        // sans doublon
    }

    @Test func sevenZipLookupAcceptsEveryBinaryOfTheFamily() {
        // La formule `sevenzip` fournit `7zz`, p7zip fournit `7z` et `7za`, et
        // `7zr` est la version réduite — limitée au .7z, précisément notre cas.
        // N'en connaître qu'un ferait échouer l'extraction sur les autres.
        let accepted = ["7zz", "7z", "7za", "7zr"]
        let found = accepted.compactMap { ModZipInstaller.firstAvailableTool(named: [$0]) }
        // Sur une machine sans aucun d'eux, le repli `unar` doit exister ou
        // `find7zTool()` renvoyer nil — jamais un chemin fantaisiste.
        if found.isEmpty {
            let fallback = ModZipInstaller.find7zTool()
            #expect(fallback == nil || fallback!.path.hasSuffix("/unar"))
        } else {
            #expect(ModZipInstaller.find7zTool() != nil)
        }
    }

    @Test func mixedNestedAndRootInstallsFlat() throws {
        // Guard: one nested entry + one root entry → no single shared parent
        // → both stay at their natural (leaf) dest, no forced grouping.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try makeModFolder(base: dir, relativePath: "A/X", uniqueId: "mod.x", name: "X")
        try makeModFolder(base: dir, relativePath: "Y", uniqueId: "mod.y", name: "Y")

        let info = ModZipInstaller().analyzeExtractedDir(at: dir, zipName: "mix.zip", existingMods: [])

        #expect(info.detectedMods.count == 2)
        #expect(Set(info.detectedMods.map { $0.folderName }) == ["X", "Y"])
    }
}

/// Le conseil donné après un refus doit correspondre à la raison du refus.
///
/// Le principe est déjà écrit dans `ZipModInfo.swift` pour `.unsupportedFormat` :
/// « annoncer *archive corrompue* sur un `.7z` parfaitement sain envoie
/// l'utilisateur chercher un problème qui n'existe pas ». Il ne s'appliquait
/// pas à `.invalidStructure`.
struct ZipRecoveryHintTests {
    @Test func aCorruptedArchiveIsWorthRedownloading() {
        #expect(ValidationStatus.corrupted.recoveryHintKey == L10n.ModInstall.recoverZip)
    }

    @Test func anIntactArchiveThatIsNotAModIsNotWorthRedownloading() {
        // Cas réel : `Cloth And Colors Bag` (Nexus 50108) est une archive
        // parfaitement saine contenant un unique fichier de configuration pour
        // ItemBags. Lui conseiller de « vérifier l'intégrité du fichier »
        // envoie l'utilisateur retélécharger indéfiniment un fichier valide.
        #expect(ValidationStatus.invalidStructure.recoveryHintKey != L10n.ModInstall.recoverZip)
    }

    @Test func anIntactArchiveThatIsNotAModExplainsWhatToDo() {
        // Le refus est juste ; l'utilisateur doit quand même savoir pourquoi et
        // ce qu'il lui reste à faire.
        #expect(ValidationStatus.invalidStructure.recoveryHintKey == L10n.ModInstall.notAModHint)
    }

    @Test func anUnsupportedFormatIsNotAnIntegrityProblemEither() {
        #expect(ValidationStatus.unsupportedFormat("7z").recoveryHintKey != L10n.ModInstall.recoverZip)
    }

    @Test func aValidArchiveHasNothingToAdvise() {
        #expect(ValidationStatus.valid.recoveryHintKey == nil)
    }
}
