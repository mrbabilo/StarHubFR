import Testing
import Foundation
@testable import StarHubTHCore

/// N-04, préalable : l'Accueil ne rescanne plus le parc à chaque arrivée,
/// seulement quand le dossier Mods ou Saves a changé depuis le dernier scan.
@Suite("Rescan à l'arrivée sur l'Accueil")
struct FolderRescanPolicyTests {

    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)

    /// Rien de changé depuis le dernier scan : pas de rescan.
    @Test func dossiersInchangesNeRescannentPas() {
        let stamps = FolderStamps(mods: t0, saves: t0)
        #expect(!FolderRescanPolicy.needsRescan(last: stamps, now: stamps))
    }

    /// Un mod ajouté, supprimé ou mis en pause dans le Finder change la date
    /// du dossier Mods ; une partie copiée ou supprimée, celle de Saves.
    @Test func unDossierModifieRescanne() {
        let last = FolderStamps(mods: t0, saves: t0)
        #expect(FolderRescanPolicy.needsRescan(last: last, now: FolderStamps(mods: t1, saves: t0)))
        #expect(FolderRescanPolicy.needsRescan(last: last, now: FolderStamps(mods: t0, saves: t1)))
    }

    /// Le disque externe du parc démonté : le dossier devient illisible, le
    /// rescan doit le montrer plutôt que garder l'ancienne liste.
    @Test func unDossierDevenuIllisibleRescanne() {
        let last = FolderStamps(mods: t0, saves: t0)
        #expect(FolderRescanPolicy.needsRescan(last: last, now: FolderStamps(mods: nil, saves: t0)))
    }

    /// Aucun scan encore daté (lancement en cours, ou dossier de jeu pas
    /// choisi) : l'Accueil ne lance rien, le chargement s'en charge.
    @Test func sansScanDateNeRescannePas() {
        #expect(!FolderRescanPolicy.needsRescan(last: nil, now: FolderStamps(mods: t1, saves: t1)))
    }

    /// La lecture des dates sur un vrai dossier : un fichier ajouté change la
    /// date du dossier, un fichier modifié dedans non.
    @Test func lectureDesDatesSurDisque() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderRescanPolicyTests-\(UUID().uuidString)")
        let mods = root.appendingPathComponent("Mods")
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.setAttributes([.modificationDate: t0], ofItemAtPath: mods.path)

        let before = FolderStamps.read(mods: mods, saves: root.appendingPathComponent("absent"))
        #expect(before.mods == t0)
        #expect(before.saves == nil)

        try Data("{}".utf8).write(to: mods.appendingPathComponent("NewMod"))
        let after = FolderStamps.read(mods: mods, saves: root.appendingPathComponent("absent"))
        #expect(FolderRescanPolicy.needsRescan(last: before, now: after))
    }
}
