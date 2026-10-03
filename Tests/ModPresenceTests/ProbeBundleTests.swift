import Foundation
import Testing
@testable import StarHubTHCore

/// D4-T3 — la sonde embarquée : quoi proposer, où écrire, quoi garder.
@Suite struct ProbeBundleTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ text: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func actionComparesVersions() {
        #expect(ProbeBundle.action(bundled: nil, presence: .absent) == .unavailable)
        #expect(ProbeBundle.action(bundled: "0.9.0", presence: .absent) == .install(version: "0.9.0"))
        #expect(ProbeBundle.action(bundled: "0.9.0", presence: .enabled(folderName: "P", version: "0.8.2"))
                == .update(from: "0.8.2", to: "0.9.0"))
        #expect(ProbeBundle.action(bundled: "0.9.0", presence: .paused(folderName: "P", version: "0.9.0"))
                == .upToDate(version: "0.9.0"))
        #expect(ProbeBundle.action(bundled: "0.9.0", presence: .enabled(folderName: "P", version: "0.10.0"))
                == .newerInstalled(installed: "0.10.0", bundled: "0.9.0"))
    }

    /// Le dossier réel : logique, en pause, composant d'un pack en pause ;
    /// rien d'inventé quand aucun n'existe.
    @Test func targetResolvesTheRealFolder() throws {
        let mods = try tempDir()
        defer { try? FileManager.default.removeItem(at: mods) }
        #expect(ProbeBundle.target(modsRoot: mods, presence: .absent)?.lastPathComponent == "StarHubFR Probe")
        #expect(ProbeBundle.target(modsRoot: mods, presence: .paused(folderName: "Probe", version: "1")) == nil)

        try FileManager.default.createDirectory(at: mods.appendingPathComponent(".Probe"), withIntermediateDirectories: true)
        #expect(ProbeBundle.target(modsRoot: mods, presence: .paused(folderName: "Probe", version: "1"))?.lastPathComponent == ".Probe")

        try FileManager.default.createDirectory(at: mods.appendingPathComponent(".Pack/Probe"), withIntermediateDirectories: true)
        let component = ProbeBundle.target(modsRoot: mods, presence: .paused(folderName: "Pack/Probe", version: "1"))
        #expect(component?.path.hasSuffix("/.Pack/Probe") == true)
    }

    /// Une mise à jour remplace ce que l'app livre et garde `config.json`,
    /// même dans un dossier en 0555.
    @Test func installReplacesShippedFilesAndKeepsTheRest() throws {
        let root = try tempDir()
        defer {
            ModZipInstaller.grantOwnerWriteAccess(in: root)
            try? FileManager.default.removeItem(at: root)
        }
        let source = root.appendingPathComponent("bundle/StarHubFR Probe")
        try write(#"{"Name":"StarHubFR Probe","Version":"0.9.0"}"#, source.appendingPathComponent("manifest.json"))
        try write("new", source.appendingPathComponent("StarHubFR.Probe.dll"))
        try write("{}", source.appendingPathComponent("i18n/fr.json"))

        let target = root.appendingPathComponent("Mods/StarHubFR Probe")
        try write(#"{"Version":"0.8.0"}"#, target.appendingPathComponent("manifest.json"))
        try write("old", target.appendingPathComponent("StarHubFR.Probe.dll"))
        try write(#"{"MeasureHarmonyPatches":true}"#, target.appendingPathComponent("config.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: target.path)

        try ProbeBundle.install(from: source, into: target)
        #expect(ProbeBundle.version(ofFolder: target) == "0.9.0")
        #expect(try String(contentsOf: target.appendingPathComponent("StarHubFR.Probe.dll"), encoding: .utf8) == "new")
        #expect(try String(contentsOf: target.appendingPathComponent("config.json"), encoding: .utf8)
                == #"{"MeasureHarmonyPatches":true}"#)
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("i18n/fr.json").path))
    }

    @Test func bundledFolderNeedsAManifest() throws {
        let resources = try tempDir()
        defer { try? FileManager.default.removeItem(at: resources) }
        #expect(ProbeBundle.bundledFolder(resourcesURL: resources) == nil)
        #expect(ProbeBundle.bundledFolder(resourcesURL: nil) == nil)
        try write("{}", resources.appendingPathComponent("Probe/StarHubFR Probe/manifest.json"))
        #expect(ProbeBundle.bundledFolder(resourcesURL: resources) != nil)
    }
}
