import Foundation
import Testing
@testable import StarHubTHCore

/// **B6-T1 — la partie lue une fois, écrite d'un coup sous garde.**
///
/// La garde vise le cas qui perd du jeu sans bruit : l'écran d'édition a lu la
/// partie, le jeu (ou une autre fenêtre) la réécrit, puis l'utilisateur
/// enregistre — l'ancienne version écraserait la nouvelle.
@Suite struct SaveDocumentTests {
    private let xml = """
        <?xml version="1.0" encoding="utf-8"?>\
        <SaveGame xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
        <player><name>Jemila</name><money>100</money>\
        <items><Item xsi:type="Object"><name>Parsnip</name><itemId>24</itemId><stack>3</stack></Item>\
        <Item xsi:nil="true" /></items>\
        <questLog><Quest><_questTitle>La Quête</_questTitle></Quest></questLog></player>\
        </SaveGame>
        """

    private func makeSave(_ env: TestEnvironment, bom: Bool = false) throws -> SaveGameInfo {
        let info = try env.makeSave(named: "Doc_1", content: xml)
        if bom { try (SaveManager.utf8BOM + Data(xml.utf8)).write(to: info.fileURL) }
        return info
    }

    private func text(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

    @Test func opensTreeAndStampFromTheSameBytes() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(env)

        let save = try SaveDocument(contentsOf: info.fileURL)

        #expect(save.player?.elements(forName: "name").first?.stringValue == "Jemila")
        #expect(save.stamp == SaveDocument.Stamp.current(of: info.fileURL))
        #expect(save.stamp.size == Data(xml.utf8).count)
    }

    @Test func malformedOrMissingFileIsRefusedAtOpen() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try env.makeSave(named: "Casse_1", content: "<SaveGame><player>")

        #expect(throws: SaveDocument.Failure.malformed) { try SaveDocument(contentsOf: info.fileURL) }
        #expect(throws: SaveDocument.Failure.unreadable) {
            try SaveDocument(contentsOf: env.savesDir.appendingPathComponent("Absente"))
        }
    }

    @Test func writesEditBacksUpFirstAndKeepsUnderscoreElements() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(env)
        let save = try SaveDocument(contentsOf: info.fileURL)
        save.player?.elements(forName: "money").first?.stringValue = "999"

        var backedUpBeforeWrite = false
        try save.write(backup: {
            backedUpBeforeWrite = text(info.fileURL).contains("<money>100</money>")
            return true
        })

        #expect(backedUpBeforeWrite)
        let written = text(info.fileURL)
        #expect(written.contains("<money>999</money>"))
        #expect(written.contains("<_questTitle>La Quête</_questTitle>"))
    }

    @Test func fileChangedSinceOpenIsNeverOverwritten() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(env)
        let save = try SaveDocument(contentsOf: info.fileURL)
        save.player?.elements(forName: "money").first?.stringValue = "999"
        // Le jeu sauvegarde entre l'ouverture et l'écriture.
        let newer = xml.replacingOccurrences(of: "<money>100</money>", with: "<money>5000</money>")
        try Data(newer.utf8).write(to: info.fileURL)

        var backupCalled = false
        #expect(throws: SaveDocument.Failure.changedOnDisk) {
            try save.write(backup: { backupCalled = true; return true })
        }
        #expect(!backupCalled)
        #expect(text(info.fileURL) == newer)
    }

    @Test func fileChangedSinceEarlierReadIsRefused() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(env)
        let shown = try SaveDocument(contentsOf: info.fileURL).stamp   // l'écran a lu
        let newer = xml.replacingOccurrences(of: "<money>100</money>", with: "<money>5000</money>")
        try Data(newer.utf8).write(to: info.fileURL)
        let save = try SaveDocument(contentsOf: info.fileURL)           // relu à l'enregistrement

        #expect(throws: SaveDocument.Failure.changedOnDisk) {
            try save.write(expected: shown, backup: { true })
        }
        #expect(text(info.fileURL) == newer)
    }

    @Test func gameRunningAtWriteTimeIsRefused() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(env)
        let save = try SaveDocument(contentsOf: info.fileURL)
        save.player?.elements(forName: "money").first?.stringValue = "999"

        #expect(throws: SaveDocument.Failure.gameRunning) {
            try save.write(isGameRunning: { true }, backup: { true })
        }
        #expect(text(info.fileURL) == xml)
    }

    @Test func failedBackupWritesNothing() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(env)
        let save = try SaveDocument(contentsOf: info.fileURL)
        save.player?.elements(forName: "money").first?.stringValue = "999"

        #expect(throws: SaveDocument.Failure.backupFailed) { try save.write(backup: { false }) }
        #expect(text(info.fileURL) == xml)
    }

    @Test func byteOrderMarkIsGivenBack() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(env, bom: true)
        let save = try SaveDocument(contentsOf: info.fileURL)

        try save.write(backup: { true })

        #expect(try Data(contentsOf: info.fileURL).starts(with: SaveManager.utf8BOM))
    }

    /// Bout en bout par `SaveManager` : le sac lu, la partie réécrite par le
    /// jeu, l'enregistrement du sac refusé.
    @Test func inventoryWriteRefusedWhenSaveChangedSinceFetch() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(env)
        let manager = SaveManager()
        var items = try #require(manager.fetchInventory(for: info))
        items[0].stack = 7
        let newer = xml.replacingOccurrences(of: "<money>100</money>", with: "<money>5000</money>")
        try Data(newer.utf8).write(to: info.fileURL)

        #expect(!manager.updateInventory(info: info, items: items))
        #expect(text(info.fileURL) == newer)
    }

    @Test func inventoryCanBeSavedTwiceFromOneFetch() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(env)
        let manager = SaveManager()
        var items = try #require(manager.fetchInventory(for: info))

        items[0].stack = 7
        #expect(manager.updateInventory(info: info, items: items))
        items[0].stack = 8
        #expect(manager.updateInventory(info: info, items: items))
        #expect(manager.fetchInventory(for: info)?.first?.stack == 8)
    }
    /// La fiche du fermier passe par l'arbre : champ édité, quête intacte, et
    /// une valeur à caractère XML échappée une seule fois.
    @Test func farmerSheetGoesThroughTheTree() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try makeSave(env)

        #expect(SaveManager().updateSave(
            info: info, newName: "D&D", newFarm: "Ferme", newFav: "", newMoney: 4321,
            newTotalMoneyEarned: 0, newMaxHealth: 100, newMaxStamina: 270,
            newGoldenWalnuts: 0, newQiGems: 0, newClubCoins: 0, newSpouse: ""))

        let written = text(info.fileURL)
        #expect(written.contains("<name>D&amp;D</name>"))
        #expect(written.contains("<money>4321</money>"))
        #expect(written.contains("<_questTitle>La Quête</_questTitle>"))
    }
}
