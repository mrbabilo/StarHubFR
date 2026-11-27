import Foundation
import Testing
@testable import StarHubTHCore

/// **X158 — une partie éditée doit porter son nouveau nom à l'écran de
/// chargement du jeu.**
///
/// `updateSave` n'écrivait que le fichier principal. L'écran de chargement lit
/// `SaveGameInfo` (un `<Farmer>` seul, sans bloc `<player>`) : nom, ferme et
/// argent y restaient anciens jusqu'à la sauvegarde suivante du jeu.
@Suite struct SaveGameInfoSyncTests {
    private static let bom = Data([0xEF, 0xBB, 0xBF])

    private func mainXML() -> String {
        """
        <?xml version="1.0" encoding="utf-8"?><SaveGame><player><name>Alice</name>\
        <farmName>Ferme</farmName><favoriteThing>Thé</favoriteThing><money>500</money>\
        <totalMoneyEarned>500</totalMoneyEarned><maxHealth>100</maxHealth>\
        <maxStamina>270</maxStamina><qiGems>0</qiGems><clubCoins>0</clubCoins>\
        </player><goldenWalnuts>0</goldenWalnuts></SaveGame>
        """
    }

    private func infoXML() -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>\
        <Farmer xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><name>Alice</name>\
        <items><Item xsi:type="Object"><name>Houe</name><stack>1</stack></Item></items>\
        <farmName>Ferme</farmName><favoriteThing>Thé</favoriteThing><money>500</money>\
        <totalMoneyEarned>500</totalMoneyEarned><maxHealth>100</maxHealth>\
        <maxStamina>270</maxStamina><qiGems>0</qiGems><clubCoins>0</clubCoins></Farmer>
        """
    }

    private func makeSave(in env: TestEnvironment, withInfo: Bool = true) throws -> SaveGameInfo {
        let name = "Chargement_1"
        let folderURL = env.savesDir.appendingPathComponent(name, isDirectory: true)
        let fileURL = folderURL.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data(mainXML().utf8).write(to: fileURL)
        if withInfo {
            try (Self.bom + Data(infoXML().utf8)).write(to: folderURL.appendingPathComponent("SaveGameInfo"))
        }
        return makeTestSave(folderName: name, fileURL: fileURL)
    }

    private func edit(_ info: SaveGameInfo, with manager: SaveManager) -> Bool {
        manager.updateSave(info: info, newName: "Bérénice", newFarm: "Les Saules & Co",
                           newFav: "Café", newMoney: 9999, newTotalMoneyEarned: 12000,
                           newMaxHealth: 150, newMaxStamina: 300, newGoldenWalnuts: 5,
                           newQiGems: 7, newClubCoins: 8, newSpouse: "")
    }

    @Test func editedFieldsReachSaveGameInfo() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(in: env)
        #expect(edit(info, with: SaveManager()))

        let url = info.fileURL.deletingLastPathComponent().appendingPathComponent("SaveGameInfo")
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written.contains("<name>Bérénice</name>"))
        #expect(written.contains("<farmName>Les Saules &amp; Co</farmName>"))
        #expect(written.contains("<favoriteThing>Café</favoriteThing>"))
        #expect(written.contains("<money>9999</money>"))
        #expect(written.contains("<totalMoneyEarned>12000</totalMoneyEarned>"))
        #expect(written.contains("<maxHealth>150</maxHealth>"))
        #expect(written.contains("<maxStamina>300</maxStamina>"))
        #expect(written.contains("<qiGems>7</qiGems>"))
        #expect(written.contains("<clubCoins>8</clubCoins>"))
    }

    /// Seuls les enfants directs du `<Farmer>` changent : le `<name>` d'un
    /// objet du sac, placé avant celui du fermier dans certaines parties, reste.
    @Test func nestedNamesAndByteOrderMarkStay() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(in: env)
        #expect(edit(info, with: SaveManager()))

        let url = info.fileURL.deletingLastPathComponent().appendingPathComponent("SaveGameInfo")
        let data = try Data(contentsOf: url)
        #expect(data.prefix(3) == Self.bom)
        let written = String(decoding: data, as: UTF8.self)
        #expect(written.contains("<Item xsi:type=\"Object\"><name>Houe</name>"))
        #expect(!written.contains("goldenWalnuts"))
    }

    @Test func saveWithoutSaveGameInfoStillSucceeds() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(in: env, withInfo: false)
        #expect(edit(info, with: SaveManager()))
        let url = info.fileURL.deletingLastPathComponent().appendingPathComponent("SaveGameInfo")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
