import Foundation
import Testing
@testable import StarHubTHCore

/// A1-T10 — le fil backup → calcul → écriture, contre un dossier
/// temporaire (jamais le vrai dossier de sauvegardes). Le store est
/// @MainActor : la suite aussi.
@Suite @MainActor struct SaveCleanupStoreTests {
    private func mod(_ id: String, enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: id, name: id, folderName: id, version: "1",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [])
    }

    private func save(_ url: URL) -> SaveGameInfo {
        SaveGameInfo(
            folderName: "Zofia_1", fileURL: url, lastModified: Date(),
            playerName: "Zofia", farmName: "F", favoriteThing: "", money: 0,
            spouse: "", maxHealth: 100, maxStamina: 270, goldenWalnuts: 0,
            qiGems: 0, clubCoins: 0, totalMoneyEarned: 0,
            year: 1, season: 0, day: 1, whichFarm: 0)
    }

    /// Un dossier de save factice `Zofia_1/Zofia_1` (+ `SaveGameInfo`) ;
    /// le backup est copié dans la racine, à côté du dossier.
    private func dossierDeSave(_ contenu: Data) throws -> (racine: URL, fichier: URL) {
        let racine = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleanup-\(UUID().uuidString)")
        let dossier = racine.appendingPathComponent("Zofia_1")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let fichier = dossier.appendingPathComponent("Zofia_1")
        try contenu.write(to: fichier)
        try Data().write(to: dossier.appendingPathComponent("SaveGameInfo"))
        return (racine, fichier)
    }

    private let verrou = SavesStore(tagForSave: { _ in "" })

    private func backups(in racine: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: racine.path)
            .filter { $0.hasPrefix("Zofia_1.backup_") }
    }

    private static let avecClé = "<modData><item><key><string>smapi/mod-data/gone.g/x</string></key>"
        + "<value><string>1</string></value></item></modData>"

    @Test("Le nettoyage supprime, écrit, et laisse un backup complet de l'original")
    func cleanupWritesAndBacksUp() async throws {
        let (racine, fichier) = try dossierDeSave(Data(Self.avecClé.utf8))
        defer { try? FileManager.default.removeItem(at: racine) }
        let store = SaveCleanupStore()
        await store.nettoyer(save: save(fichier), mods: [], verrou: verrou)
        #expect(store.phase == .terminé(supprimées: 1, laissées: 0))
        #expect(try String(contentsOf: fichier, encoding: .utf8) == "<modData></modData>")
        let backups = try FileManager.default.contentsOfDirectory(atPath: racine.path)
            .filter { $0.hasPrefix("Zofia_1.backup_") }
        #expect(backups.count == 1)
        let copie = racine.appendingPathComponent(backups[0]).appendingPathComponent("Zofia_1")
        #expect(try Data(contentsOf: copie) == Data(Self.avecClé.utf8))
    }

    @Test("Aucune clé à supprimer : échec `.aucuneClé`, octets inchangés")
    func cleanupWithoutKeysWritesNothing() async throws {
        let contenu = Data("<modData></modData>".utf8)
        let (racine, fichier) = try dossierDeSave(contenu)
        defer { try? FileManager.default.removeItem(at: racine) }
        let store = SaveCleanupStore()
        await store.nettoyer(save: save(fichier), mods: [mod("Absent.A")], verrou: verrou)
        #expect(store.phase == .échec(.aucuneClé))
        #expect(try Data(contentsOf: fichier) == contenu)
        // Rien à retirer : pas de backup laissé pour rien dans Saves/.
        #expect(try backups(in: racine).isEmpty)
    }

    @Test("Le BOM de tête est préservé, SaveGameInfo jamais touché")
    func writeKeepsBOMAndLeavesSaveGameInfo() async throws {
        let bom = Data([0xEF, 0xBB, 0xBF])
        let (racine, fichier) = try dossierDeSave(bom + Data(Self.avecClé.utf8))
        defer { try? FileManager.default.removeItem(at: racine) }
        let store = SaveCleanupStore()
        await store.nettoyer(save: save(fichier), mods: [], verrou: verrou)
        #expect(store.phase == .terminé(supprimées: 1, laissées: 0))
        #expect(try Data(contentsOf: fichier) == bom + Data("<modData></modData>".utf8))
        let sgi = try Data(contentsOf: fichier.deletingLastPathComponent()
            .appendingPathComponent("SaveGameInfo"))
        #expect(sgi.isEmpty)
    }

    @Test("Backup impossible : échec `.backup`, fichier inchangé")
    func failedBackupWritesNothing() async throws {
        let contenu = Data(Self.avecClé.utf8)
        let (racine, fichier) = try dossierDeSave(contenu)
        // Le parent du dossier en lecture seule : la copie du backup échoue.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: racine.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: racine.path)
            try? FileManager.default.removeItem(at: racine)
        }
        let store = SaveCleanupStore()
        await store.nettoyer(save: save(fichier), mods: [], verrou: verrou)
        #expect(store.phase == .échec(.backup))
        #expect(try Data(contentsOf: fichier) == contenu)
    }

    @Test("Une autre opération tient le verrou des saves : rien n'est écrit")
    func busyLockWritesNothing() async throws {
        let contenu = Data(Self.avecClé.utf8)
        let (racine, fichier) = try dossierDeSave(contenu)
        defer { try? FileManager.default.removeItem(at: racine) }
        #expect(verrou.beginOperation())
        let store = SaveCleanupStore()
        await store.nettoyer(save: save(fichier), mods: [], verrou: verrou)
        #expect(store.phase == .échec(.occupé))
        #expect(try Data(contentsOf: fichier) == contenu)
        #expect(try backups(in: racine).isEmpty)
        #expect(verrou.isOperationRunning)   // le verrou d'autrui reste pris
    }

    @Test("Le verrou est relâché après un nettoyage, réussi ou non")
    func lockIsReleased() async throws {
        let (racine, fichier) = try dossierDeSave(Data("<modData></modData>".utf8))
        defer { try? FileManager.default.removeItem(at: racine) }
        let store = SaveCleanupStore()
        await store.nettoyer(save: save(fichier), mods: [], verrou: verrou)
        #expect(!verrou.isOperationRunning)
    }

    @Test("Deux backups dans la même seconde ne se marchent pas dessus")
    func sameSecondBackupsDoNotCollide() throws {
        let (racine, fichier) = try dossierDeSave(Data(Self.avecClé.utf8))
        defer { try? FileManager.default.removeItem(at: racine) }
        let premier = SaveManager.shared.backupSaveURL(info: save(fichier))
        let second = SaveManager.shared.backupSaveURL(info: save(fichier))
        #expect(premier != nil && second != nil && premier != second)
        #expect(try backups(in: racine).count == 2)
    }
}

