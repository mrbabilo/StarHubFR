import Foundation
import Testing
@testable import StarHubTHCore

/// **Audit UX 2026-11-27, F1 — un seul enregistrement pour la fiche et le sac.**
/// Deux boutons, deux écritures : cliquer l'un perdait ce qu'on avait saisi
/// dans l'autre.
@Suite struct SaveEditsTests {
    private let xml = """
        <?xml version="1.0" encoding="utf-8"?><SaveGame xmlns:xsi="x"><player><name>Jemila</name>\
        <money>100</money><items><Item xsi:type="Object"><name>Parsnip</name><itemId>24</itemId>\
        <stack>3</stack></Item></items></player></SaveGame>
        """

    private func backups(of info: SaveGameInfo) throws -> Int {
        let parent = info.fileURL.deletingLastPathComponent().deletingLastPathComponent()
        return try FileManager.default.contentsOfDirectory(atPath: parent.path).filter { $0.contains(".backup_") }.count
    }

    @Test func sheetAndBagAreWrittenTogetherWithOneBackup() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try env.makeSave(named: "Edits_1", content: xml)
        let manager = SaveManager(isGameRunning: { false })
        let save = try #require(manager.parseSaveFile(url: info.fileURL, folderName: "Edits_1"))
        var items = try #require(manager.fetchInventory(for: save))
        items[0].stack = 9
        var draft = SaveFarmerDraft(save)
        draft.money = "4321"

        try manager.writeEdits(info: save, sheet: draft.sheet(for: save), items: items, overwriteNewer: false)

        let written = try String(contentsOf: info.fileURL, encoding: .utf8)
        #expect(written.contains("<money>4321</money>"))
        #expect(written.contains("<stack>9</stack>"))
        #expect(try backups(of: info) == 1)
    }

    @Test func theBagAloneKeepsItsScreenTimeGuard() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try env.makeSave(named: "Edits_2", content: xml)
        let manager = SaveManager(isGameRunning: { false })
        var items = try #require(manager.fetchInventory(for: info))
        items[0].stack = 9
        let newer = xml.replacingOccurrences(of: "<money>100</money>", with: "<money>5000</money>")
        try Data(newer.utf8).write(to: info.fileURL)

        #expect(throws: SaveDocument.Failure.changedOnDisk) {
            try manager.writeEdits(info: info, sheet: nil, items: items, overwriteNewer: false)
        }
        #expect(try String(contentsOf: info.fileURL, encoding: .utf8) == newer)
    }

    @Test func changesAreCountedFieldBySlotBySlot() {
        let save = makeTestSave(folderName: "C", fileURL: URL(fileURLWithPath: "/tmp/C"))
        let initial = SaveFarmerDraft(save)
        var draft = initial
        #expect(draft.changedFields(from: initial) == 0)
        draft.money = "1"
        draft.name = "Autre"
        #expect(draft.changedFields(from: initial) == 2)

        let loaded = [InventoryItem(slotIndex: 0, itemId: "24", name: "Parsnip", stack: 3, isObject: true),
                      InventoryItem.empty(slot: 1)]
        var edited = loaded
        #expect(InventoryItem.changedSlots(edited, from: loaded) == 0)
        edited[0].stack = 4
        #expect(InventoryItem.changedSlots(edited, from: loaded) == 1)
    }
}
