import Foundation
import Testing
@testable import StarHubTHCore

/// A1-T11 — l'installateur applique le plan du tri dans la branche
/// `.overwriteWithBackup` : fantômes non remis, retouches et fichiers
/// locaux remis, suppressions respectées ; sans plan, rien ne change.
@Suite struct UpdateTriageInstallTests {
    private func write(_ content: String, base: URL, relativePath: String) throws {
        let url = base.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(toFile: url.path, atomically: true, encoding: .utf8)
    }

    private func read(_ base: URL, _ relativePath: String) -> String? {
        try? String(contentsOf: base.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private struct Setup {
        let env: InstallerTestEnv
        let mod: DetectedMod
        let existing: ModItem
    }

    /// Existant `SampleMod` : un fantôme d'une vieille version, une retouche,
    /// une donnée de partie, un `config.json`. Archive neuve : `retouch.png`
    /// changé par l'auteur et `deleted.png`, que l'utilisateur avait supprimé.
    private func setup() throws -> Setup {
        let env = InstallerTestEnv()
        try makeModFolder(base: env.modsDir, relativePath: "SampleMod", uniqueId: "a.sample", name: "Sample")
        try makeModFolder(base: env.tempExtractDir, relativePath: "SampleMod", uniqueId: "a.sample", name: "Sample")
        try write("ghost", base: env.modsDir, relativePath: "SampleMod/ghost.png")
        try write("mine", base: env.modsDir, relativePath: "SampleMod/retouch.png")
        try write("save", base: env.modsDir, relativePath: "SampleMod/data/game_1_SaveData.save")
        try write(#"{"User":true}"#, base: env.modsDir, relativePath: "SampleMod/config.json")
        try write("v2", base: env.tempExtractDir, relativePath: "SampleMod/retouch.png")
        try write("v2", base: env.tempExtractDir, relativePath: "SampleMod/deleted.png")
        try write(#"{"Author":true}"#, base: env.tempExtractDir, relativePath: "SampleMod/config.json")
        let existing = ModItem(uniqueId: "a.sample", name: "Sample", folderName: "SampleMod",
                               version: "1.0.0", author: "A", description: "", nexusUrl: "",
                               nexusModId: "", isEnabled: true, dependencies: [], children: nil,
                               isGroup: false)
        let mod = DetectedMod(folderName: "SampleMod", relativePath: "SampleMod",
                              manifest: parsedManifest(uniqueId: "a.sample", name: "Sample"),
                              hasConfigFiles: false, dependencies: [], dependencyDetails: [],
                              existingVersion: existing)
        return Setup(env: env, mod: mod, existing: existing)
    }

    /// Le journal local dit ce que la 1.0.0 avait posé : `ghost.png` (ces
    /// octets), `retouch.png` (« v1 »), `deleted.png`.
    private func provider() -> UpdateTriageProvider {
        UpdateTriageProvider { existing, installedFolder, newSource in
            let installed = ModFolderHasher.listing(of: installedFolder)
            let local = AuthorFileIndex.Version(
                source: .localHistory, version: existing.version,
                files: ["ghost.png": installed.hashes["ghost.png"] ?? "",
                        "retouch.png": "v1-sha", "deleted.png": "v1-sha"])
            return UpdateFileTriage.plan(installed: installed,
                                         newArchive: ModFolderHasher.listing(of: newSource),
                                         index: AuthorFileIndex(versions: [local]),
                                         installedVersion: existing.version, deposits: [])
        }
    }

    private func install(_ setup: Setup, triage: UpdateTriageProvider?) throws -> [InstalledModPath] {
        let installer = ModZipInstaller(backupManager: setup.env.backupManager)
        let selection = InstallSelection(modId: setup.mod.id, selected: true,
                                         conflictResolution: .overwriteWithBackup)
        return try installer.install(from: setup.env.tempExtractDir, to: setup.env.modsDisabledDir.path,
                                     selections: [selection], detectedMods: [setup.mod],
                                     gameDir: setup.env.gameDir, existingMods: [setup.existing],
                                     triage: triage)
    }

    @Test func thePlanDecidesWhatComesBack() throws {
        let setup = try setup()
        defer { setup.env.cleanup() }
        let written = try install(setup, triage: provider())
        let folder = setup.env.modsDir.appendingPathComponent("SampleMod")
        #expect(read(folder, "ghost.png") == nil, "fantôme non remis")
        #expect(read(folder, "retouch.png") == "mine", "retouche gardée")
        #expect(read(folder, "data/game_1_SaveData.save") == "save", "donnée de partie gardée")
        #expect(read(folder, "config.json") == #"{"User":true}"#)
        #expect(read(folder, "deleted.png") == nil, "suppression respectée")
        let report = try #require(written.first?.triage?.report)
        #expect(report.removedGhosts == ["ghost.png"])
        #expect(report.retouchesAuthorChanged == ["retouch.png"])
        #expect(report.respectedDeletions == ["deleted.png"])
    }

    /// Sans fournisseur : le comportement d'avant (A1-T7 remet le fantôme,
    /// l'archive écrase la retouche, repose `deleted.png`).
    @Test func withoutTriageNothingChanges() throws {
        let setup = try setup()
        defer { setup.env.cleanup() }
        let written = try install(setup, triage: nil)
        let folder = setup.env.modsDir.appendingPathComponent("SampleMod")
        #expect(read(folder, "ghost.png") == "ghost")
        #expect(read(folder, "retouch.png") == "v2")
        #expect(read(folder, "deleted.png") == "v2")
        #expect(written.first?.triage == nil)
    }
}
