import Foundation
import Testing
@testable import StarHubTHCore

/// A1-T2 — retrouver un manifeste sain dans les backups d'installation et
/// le recopier. Arbres réels (backup = dossier complet du mod) dans des
/// dossiers temporaires : le format sur disque est la donnée critique,
/// `backupPath/<folderName>/manifest.json`.
@Suite struct ManifestRepairTests {

    private let fm = FileManager.default

    /// Un backup d'installation : `<racine>/<mod>/manifest.json`.
    @discardableResult
    private func makeBackup(name: String, manifest: String,
                            date: Date) throws -> ManifestRepair.BackupCandidate {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let modDir = root.appendingPathComponent(name)
        try fm.createDirectory(at: modDir, withIntermediateDirectories: true)
        try manifest.write(to: modDir.appendingPathComponent("manifest.json"),
                           atomically: true, encoding: .utf8)
        return ManifestRepair.BackupCandidate(timestamp: date, originalFolderName: name,
                                              backupPath: root.path)
    }

    private let healthyManifest = """
    {
        "Name": "Cheats Menu",
        "Version": "1.2.3",
        "UniqueID": "CJB.CheatsMenu"
    }
    """

    @Test func picksTheMostRecentBackupCarryingTheManifest() throws {
        let old = try makeBackup(name: "Broken",
                                 manifest: healthyManifest,
                                 date: Date(timeIntervalSince1970: 100))
        let recent = try makeBackup(name: "Broken",
                                    manifest: healthyManifest,
                                    date: Date(timeIntervalSince1970: 200))
        // Un backup d'un AUTRE mod, plus récent encore : ne compte pas.
        _ = try makeBackup(name: "Other",
                           manifest: healthyManifest,
                           date: Date(timeIntervalSince1970: 300))
        let found = ManifestRepair.backupManifest(folderName: "Broken",
                                                  candidates: [old, recent])
        #expect(found?.path.hasSuffix("/Broken/manifest.json") == true)
        #expect(found?.date == recent.timestamp)
    }

    @Test func emptyBackupFolderCarriesNothing() throws {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let candidate = ManifestRepair.BackupCandidate(
            timestamp: Date(), originalFolderName: "Broken", backupPath: root.path)
        #expect(ManifestRepair.backupManifest(folderName: "Broken", candidates: [candidate]) == nil)
        #expect(throws: ManifestRepair.RestoreError.noBackupManifest) {
            _ = try ManifestRepair.restore(folderName: "Broken", destinationFolder: root.path,
                                           candidates: [candidate])
        }
    }

    /// Un composant (`Racine/Composant`) vit dans le backup de sa racine :
    /// le candidat porte `Racine`, le manifeste est au sous-chemin complet.
    @Test func packComponentManifestLivesUnderItsRootBackup() throws {
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let comp = root.appendingPathComponent("Pack Root/[CP] Component")
        try fm.createDirectory(at: comp, withIntermediateDirectories: true)
        try healthyManifest.write(to: comp.appendingPathComponent("manifest.json"),
                                  atomically: true, encoding: .utf8)
        let candidate = ManifestRepair.BackupCandidate(
            timestamp: Date(timeIntervalSince1970: 10), originalFolderName: "Pack Root",
            backupPath: root.path)
        let found = ManifestRepair.backupManifest(folderName: "Pack Root/[CP] Component",
                                                  candidates: [candidate])
        #expect(found?.path.hasSuffix("/Pack Root/[CP] Component/manifest.json") == true)
    }

    /// La réparation copie le manifeste du backup dans le dossier du mod —
    /// **lui seul** : le contenu actuel reste intact, même quand le backup
    /// est plus ancien.
    @Test func restoreCopiesOnlyTheManifestIntoTheLiveFolder() throws {
        let backup = try makeBackup(name: "Broken", manifest: healthyManifest,
                                    date: Date(timeIntervalSince1970: 100))
        let modsRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let modFolder = modsRoot.appendingPathComponent("Broken")
        try fm.createDirectory(at: modFolder, withIntermediateDirectories: true)
        try "{ cassé".write(to: modFolder.appendingPathComponent("manifest.json"),
                            atomically: true, encoding: .utf8)
        try "config actuelle".write(to: modFolder.appendingPathComponent("config.json"),
                                    atomically: true, encoding: .utf8)

        let written = try ManifestRepair.restore(folderName: "Broken",
                                                 destinationFolder: modFolder.path,
                                                 candidates: [backup])
        #expect(written.hasSuffix("/Broken/manifest.json"))
        let repaired = try String(contentsOf: URL(fileURLWithPath: written), encoding: .utf8)
        #expect(repaired == healthyManifest)
        let config = try String(contentsOf: modFolder.appendingPathComponent("config.json"),
                                encoding: .utf8)
        #expect(config == "config actuelle")
    }

    /// Mod en pause : le dossier physique porte le point — c'est
    /// l'appelant qui le résout, la restauration ne devine rien.
    @Test func restoreWritesWhereTheCallerPointsIncludingAPausedFolder() throws {
        let backup = try makeBackup(name: "Broken", manifest: healthyManifest, date: Date())
        let modsRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paused = modsRoot.appendingPathComponent(".Broken")
        try fm.createDirectory(at: paused, withIntermediateDirectories: true)
        let written = try ManifestRepair.restore(folderName: "Broken",
                                                 destinationFolder: paused.path,
                                                 candidates: [backup])
        #expect(fm.fileExists(atPath: written))
    }

    @Test func restoreNamesAVanishedDestination() throws {
        let backup = try makeBackup(name: "Gone", manifest: healthyManifest, date: Date())
        let nowhere = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Gone").path
        #expect(throws: ManifestRepair.RestoreError.destinationMissing(nowhere)) {
            _ = try ManifestRepair.restore(folderName: "Gone", destinationFolder: nowhere,
                                           candidates: [backup])
        }
    }
}
