import Testing
import Foundation
@testable import StarHubTHCore

/// R1 (audit UX 2026-10-16) — la suppression depuis « Sauvegardes des mods »
/// lit la même règle « seule copie » que l'Entretien, sur le disque réel :
/// une sauvegarde au `config.json` absent du mod installé est la seule copie.
struct MaintenanceDiskReaderTests {

    private let fm = FileManager.default

    /// Une sauvegarde `<racine>/Zebrus/config.json` et un `Mods/` vide.
    private func makeTree() throws -> (backupRoot: URL, modsRoot: URL) {
        let root = fm.temporaryDirectory.appendingPathComponent("DiskReader-\(UUID().uuidString)")
        let backupRoot = root.appendingPathComponent("session/Zebrus")
        try fm.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        try Data("{\"SearchHotkey\": \"D7\"}".utf8).write(to: backupRoot.appendingPathComponent("config.json"))
        let modsRoot = root.appendingPathComponent("Mods")
        try fm.createDirectory(at: modsRoot, withIntermediateDirectories: true)
        return (backupRoot, modsRoot)
    }

    private func soleCopy(_ tree: (backupRoot: URL, modsRoot: URL)) -> [String] {
        MaintenanceDiskReader.soleCopyFiles(backupRoot: tree.backupRoot, modFolder: "Zebrus",
                                            modsRoot: tree.modsRoot.path, hostTranslationPaths: [])
            .map(\.relativePath)
    }

    @Test func aBackupOfAnUninstalledModIsTheOnlyCopyOfItsConfig() throws {
        let tree = try makeTree()
        #expect(soleCopy(tree) == ["config.json"])
    }

    @Test func aModThatStillCarriesItsConfigProtectsNothing() throws {
        let tree = try makeTree()
        let mod = tree.modsRoot.appendingPathComponent("Zebrus")
        try fm.createDirectory(at: mod, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: mod.appendingPathComponent("config.json"))
        #expect(soleCopy(tree).isEmpty)
    }

    /// Un mod en pause est installé : son dossier porte le point.
    @Test func aPausedModIsReadThroughItsDottedFolder() throws {
        let tree = try makeTree()
        let paused = tree.modsRoot.appendingPathComponent(".Zebrus")
        try fm.createDirectory(at: paused, withIntermediateDirectories: true)
        #expect(soleCopy(tree) == ["config.json"])
        try Data("{}".utf8).write(to: paused.appendingPathComponent("config.json"))
        #expect(soleCopy(tree).isEmpty)
    }

    @Test func aBackupGoneFromDiskProtectsNothing() throws {
        let tree = try makeTree()
        try fm.removeItem(at: tree.backupRoot)
        #expect(soleCopy(tree).isEmpty)
    }
}
