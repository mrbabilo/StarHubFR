import Foundation
import Testing
@testable import StarHubTHCore

/// **Stardew écrit ses sauvegardes avec une marque d'ordre des octets.**
///
/// Mesuré sur le disque de l'auteur (2026-09-03) : les **38 fichiers** produits
/// par le jeu — sauvegardes, `SaveGameInfo`, leurs `_old` et `_backup` — en
/// portent une. Les seuls fichiers qui n'en ont pas sont **trois copies de la
/// même sauvegarde**, toutes datées du 2026-08-31 23:20, et longues de
/// 37 492 144 octets contre 37 492 147 pour la version du jeu : exactement les
/// trois octets de la marque.
///
/// C'est l'app qui les a retirés. `String(contentsOf:encoding:)` consomme la
/// marque au décodage, et `write(to:atomically:encoding:)` ne la réécrit pas :
/// éditer une fiche de joueur réécrit donc le fichier dans un encodage que le
/// jeu n'emploie pas. .NET lit très bien de l'UTF-8 sans marque — aucun dégât
/// constaté — mais une sauvegarde représente des centaines d'heures, et l'app
/// n'a pas à la réécrire autrement qu'elle ne l'a lue.
@Suite struct SaveBOMPreservationTests {
    private static let bom = Data([0xEF, 0xBB, 0xBF])

    /// Une sauvegarde minimale mais réaliste : prologue, espaces de noms, et
    /// les champs que `updateSave` réécrit.
    private func saveXML(name: String, money: Int) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>\
        <SaveGame xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
        <player><name>\(name)</name><farmName>Ferme</farmName>\
        <favoriteThing>Rien</favoriteThing><money>\(money)</money>\
        <totalMoneyEarned>0</totalMoneyEarned><maxHealth>100</maxHealth>\
        <maxStamina>270</maxStamina><qiGems>0</qiGems><clubCoins>0</clubCoins>\
        <items><Item xsi:nil="true" /></items></player>\
        <goldenWalnuts>0</goldenWalnuts><whichFarm>0</whichFarm>\
        </SaveGame>
        """
    }

    private func makeSave(in env: TestEnvironment, named name: String,
                          withBOM: Bool) throws -> SaveGameInfo {
        let folderURL = env.savesDir.appendingPathComponent(name, isDirectory: true)
        let fileURL = folderURL.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        var data = withBOM ? Self.bom : Data()
        data.append(saveXML(name: name, money: 100).data(using: .utf8)!)
        try data.write(to: fileURL)
        return makeTestSave(folderName: name, fileURL: fileURL)
    }

    private func firstBytes(of url: URL) -> Data {
        (try? Data(contentsOf: url).prefix(3)) ?? Data()
    }

    @Test func editingAPlayerSheetKeepsTheByteOrderMark() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(in: env, named: "Avec", withBOM: true)

        let manager = SaveManager()
        #expect(manager.updateSave(info: info, newName: "Zofia", newFarm: "Ferme",
                                   newFav: "Rien", newMoney: 999, newTotalMoneyEarned: 0,
                                   newMaxHealth: 100, newMaxStamina: 270,
                                   newGoldenWalnuts: 0, newQiGems: 0, newClubCoins: 0,
                                   newSpouse: ""))

        #expect(firstBytes(of: info.fileURL) == Self.bom)
        // Et l'édition a bien eu lieu.
        let reread = manager.parseSaveFile(url: info.fileURL, folderName: info.folderName)
        #expect(reread?.playerName == "Zofia")
        #expect(reread?.money == 999)
    }

    @Test func aSaveWithoutTheMarkDoesNotGainOne() throws {
        // La symétrie compte : rendre le fichier tel qu'on l'a lu, pas
        // « toujours avec marque ».
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(in: env, named: "Sans", withBOM: false)

        let manager = SaveManager()
        #expect(manager.updateSave(info: info, newName: "Zofia", newFarm: "Ferme",
                                   newFav: "Rien", newMoney: 999, newTotalMoneyEarned: 0,
                                   newMaxHealth: 100, newMaxStamina: 270,
                                   newGoldenWalnuts: 0, newQiGems: 0, newClubCoins: 0,
                                   newSpouse: ""))

        #expect(firstBytes(of: info.fileURL) != Self.bom)
        #expect(manager.parseSaveFile(url: info.fileURL, folderName: info.folderName)?.money == 999)
    }

    @Test func editingTheInventoryKeepsTheByteOrderMark() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(in: env, named: "Inventaire", withBOM: true)

        let manager = SaveManager()
        let items = manager.fetchInventory(for: info) ?? []
        #expect(manager.updateInventory(info: info, items: items))
        #expect(firstBytes(of: info.fileURL) == Self.bom)
    }

    @Test func duplicatingASaveKeepsTheMarkInBothFiles() throws {
        // Troisième chemin d'écriture, celui du clonage : il patche le nom du
        // joueur et de la ferme dans **deux** fichiers — la sauvegarde et son
        // `SaveGameInfo`. Les deux étaient rendus sans la marque.
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(in: env, named: "Source", withBOM: true)
        var infoFile = Self.bom
        infoFile.append("<Farmer><name>Source</name><farmName>Ferme</farmName></Farmer>".data(using: .utf8)!)
        let saveGameInfoURL = info.fileURL.deletingLastPathComponent()
            .appendingPathComponent("SaveGameInfo")
        try infoFile.write(to: saveGameInfoURL)

        let manager = SaveManager()
        #expect(manager.duplicateSave(info: info, newName: "Copie", newFarm: "Ferme2"))

        let clone = env.savesDir.appendingPathComponent("Source_copy", isDirectory: true)
        #expect(firstBytes(of: clone.appendingPathComponent("Source_copy")) == Self.bom)
        #expect(firstBytes(of: clone.appendingPathComponent("SaveGameInfo")) == Self.bom)
        // Et le clone porte bien le nouveau nom : la marque n'a pas mangé la
        // première balise.
        #expect(manager.parseSaveFile(url: clone.appendingPathComponent("Source_copy"),
                                      folderName: "Source_copy")?.playerName == "Copie")
    }

    @Test func aMarkAtTheHeadIsNotReadAsContent() throws {
        // La marque ne doit pas non plus troubler la lecture : c'est elle qui
        // fait échouer `String(data:encoding:.utf8)` ailleurs dans le dépôt.
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(in: env, named: "Lecture", withBOM: true)

        let parsed = SaveManager().parseSaveFile(url: info.fileURL, folderName: "Lecture")
        #expect(parsed?.playerName == "Lecture")
        #expect(parsed?.money == 100)
    }
}
