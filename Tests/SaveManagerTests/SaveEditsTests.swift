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
        let read = try #require(manager.fetchContents(for: save)?.inventory)
        var items = read
        items[0].stack = 9
        var draft = SaveFarmerDraft(save)
        draft.money = "4321"

        try manager.writeEdits(info: save, sheet: draft.sheet(for: save), items: SlotEdit.changes(items, from: read),
                               chests: nil, expected: nil)

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
        let read = try #require(manager.fetchContents(for: info))
        var items = read.inventory
        items[0].stack = 9
        let newer = xml.replacingOccurrences(of: "<money>100</money>", with: "<money>5000</money>")
        try Data(newer.utf8).write(to: info.fileURL)

        #expect(throws: SaveDocument.Failure.changedOnDisk) {
            try manager.writeEdits(info: info, sheet: nil, items: SlotEdit.changes(items, from: read.inventory),
                                   chests: nil, expected: read.stamp)
        }
        #expect(try String(contentsOf: info.fileURL, encoding: .utf8) == newer)
    }

    /// A4 — une partie avec un sac, un coffre posé et un coffre Junimo posé (lu seulement).
    private let chestXML = """
        <?xml version="1.0" encoding="utf-8"?><SaveGame xmlns:xsi="x"><player><name>Jemila</name>\
        <money>100</money><items><Item xsi:type="Object"><name>Parsnip</name><itemId>24</itemId>\
        <stack>3</stack></Item></items></player><locations><GameLocation><name>Farm</name><objects>\
        <item><key><Vector2><X>1</X><Y>2</Y></Vector2></key><value><Object xsi:type="Chest"><name>Chest</name><items>\
        <Item xsi:type="Object"><name>Wood</name><itemId>388</itemId><stack>50</stack></Item></items></Object></value></item>\
        <item><key><Vector2><X>5</X><Y>6</Y></Vector2></key><value><Object xsi:type="Chest"><name>Chest</name>\
        <specialChestType>JunimoChest</specialChestType><items>\
        <Item xsi:type="Object"><name>Stone</name><itemId>390</itemId><stack>7</stack></Item></items></Object></value></item>\
        </objects></GameLocation></locations></SaveGame>
        """

    @Test func bagAndChestAreWrittenTogetherWithOneBackup() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try env.makeSave(named: "Edits_A4_1", content: chestXML)
        let manager = SaveManager(isGameRunning: { false })
        let read = try #require(manager.fetchContents(for: info))
        var items = read.inventory
        items[0].stack = 9
        let woodRead = try #require(read.chests.first { $0.id == "Farm@1,2" }?.items)
        var wood = woodRead
        wood[0].stack = 77

        try manager.writeEdits(info: info, sheet: nil, items: SlotEdit.changes(items, from: read.inventory),
                               chests: ["Farm@1,2": SlotEdit.changes(wood, from: woodRead)], expected: read.stamp)

        let written = try String(contentsOf: info.fileURL, encoding: .utf8)
        #expect(written.contains("<stack>9</stack>"))
        #expect(written.contains("<stack>77</stack>"))
        #expect(try backups(of: info) == 1)
    }

    @Test func chestEditOnChangedFileIsRefused() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try env.makeSave(named: "Edits_A4_2", content: chestXML)
        let manager = SaveManager(isGameRunning: { false })
        let read = try #require(manager.fetchContents(for: info))
        let woodRead = try #require(read.chests.first { $0.id == "Farm@1,2" }?.items)
        var wood = woodRead
        wood[0].stack = 77
        // Coffre seul : la session demande quand même l'empreinte de la lecture.
        let newer = chestXML.replacingOccurrences(of: "<money>100</money>", with: "<money>5000</money>")
        try Data(newer.utf8).write(to: info.fileURL)

        #expect(throws: SaveDocument.Failure.changedOnDisk) {
            try manager.writeEdits(info: info, sheet: nil, items: nil, chests: ["Farm@1,2": SlotEdit.changes(wood, from: woodRead)],
                                   expected: read.stamp)
        }
        #expect(try String(contentsOf: info.fileURL, encoding: .utf8) == newer)
    }

    @Test func aReadOnlyChestIsNeverWritten() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try env.makeSave(named: "Edits_A4_3", content: chestXML)
        let manager = SaveManager(isGameRunning: { false })
        let read = try #require(manager.fetchContents(for: info))
        let junimo = try #require(read.chests.first { $0.id == "Farm@5,6" })
        #expect(!junimo.isEditable)
        var stone = junimo.items
        stone[0].stack = 99
        let woodRead = try #require(read.chests.first { $0.id == "Farm@1,2" }?.items)
        var wood = woodRead
        wood[0].stack = 77

        // Un coffre en lecture seule dans le lot : tout est refusé, même l'éditable.
        #expect(throws: SaveDocument.Failure.malformed) {
            try manager.writeEdits(info: info, sheet: nil, items: nil,
                                   chests: ["Farm@1,2": SlotEdit.changes(wood, from: woodRead),
                                            "Farm@5,6": SlotEdit.changes(stone, from: junimo.items)], expected: read.stamp)
        }
        #expect(try String(contentsOf: info.fileURL, encoding: .utf8) == chestXML)
        #expect(try backups(of: info) == 0)
    }

    // MARK: - Écrasement confirmé (`expected: nil`) : seules les cases modifiées, vérifiées

    @Test func aConfirmedOverwriteWritesOnlyChangedSlotsAndKeepsNewerChanges() throws {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try env.makeSave(named: "Edits_Over_1", content: chestXML)
        let manager = SaveManager(isGameRunning: { false })
        let read = try #require(manager.fetchContents(for: info))
        var items = read.inventory
        items[0].stack = 9
        let woodRead = try #require(read.chests.first { $0.id == "Farm@1,2" }?.items)
        var wood = woodRead
        wood[0].stack = 77
        // Un jour joué depuis : argent, et la Pierre du coffre Junimo ; le Panais et le Bois sont toujours là.
        let newer = chestXML.replacingOccurrences(of: "<money>100</money>", with: "<money>5000</money>")
            .replacingOccurrences(of: "<stack>7</stack>", with: "<stack>8</stack>")
        try Data(newer.utf8).write(to: info.fileURL)

        try manager.writeEdits(info: info, sheet: nil, items: SlotEdit.changes(items, from: read.inventory),
                               chests: ["Farm@1,2": SlotEdit.changes(wood, from: woodRead)], expected: nil)

        let written = try String(contentsOf: info.fileURL, encoding: .utf8)
        #expect(written.contains("<money>5000</money>"))
        #expect(written.contains("<stack>8</stack>"))
        #expect(written.contains("<stack>9</stack>") && written.contains("<stack>77</stack>"))
    }

    @Test func aConfirmedOverwriteRefusesABagSlotTheNewerFileChanged() throws {
        let parsnip = "<Item xsi:type=\"Object\"><name>Parsnip</name><itemId>24</itemId><stack>3</stack></Item>"
        let replacements = ["<Item xsi:type=\"Object\"><name>Potato</name><itemId>192</itemId><stack>3</stack></Item>",
                            "<Item xsi:nil=\"true\" />"]
        for (index, replacement) in replacements.enumerated() {
            let env = TestEnvironment()
            defer { env.cleanup() }
            let info = try env.makeSave(named: "Edits_Over_2_\(index)", content: xml)
            let manager = SaveManager(isGameRunning: { false })
            let read = try #require(manager.fetchContents(for: info))
            var items = read.inventory
            items[0].stack = 9
            let newer = xml.replacingOccurrences(of: parsnip, with: replacement)
            #expect(newer != xml)
            try Data(newer.utf8).write(to: info.fileURL)

            #expect(throws: SaveDocument.Failure.changedOnDisk) {
                try manager.writeEdits(info: info, sheet: nil, items: SlotEdit.changes(items, from: read.inventory),
                                       chests: nil, expected: nil)
            }
            #expect(try String(contentsOf: info.fileURL, encoding: .utf8) == newer)
            #expect(try backups(of: info) == 0)
        }
    }

    @Test func aConfirmedOverwriteRefusesAChestThatMovedOrChangedSlot() throws {
        let woodChest = "<Object xsi:type=\"Chest\"><name>Chest</name><items>"
            + "<Item xsi:type=\"Object\"><name>Wood</name><itemId>388</itemId><stack>50</stack></Item></items></Object>"
        // Un autre coffre posé sur la même tuile ; le coffre parti.
        let stoneChest = woodChest.replacingOccurrences(of: "<name>Wood</name><itemId>388</itemId>",
                                                        with: "<name>Stone</name><itemId>390</itemId>")
        let gone = "<item><key><Vector2><X>1</X><Y>2</Y></Vector2></key><value>\(woodChest)</value></item>"
        #expect(chestXML.contains(woodChest) && chestXML.contains(gone))
        for (index, newer) in [chestXML.replacingOccurrences(of: woodChest, with: stoneChest),
                               chestXML.replacingOccurrences(of: gone, with: "")].enumerated() {
            let env = TestEnvironment()
            defer { env.cleanup() }
            let info = try env.makeSave(named: "Edits_Over_3_\(index)", content: chestXML)
            let manager = SaveManager(isGameRunning: { false })
            let read = try #require(manager.fetchContents(for: info))
            let woodRead = try #require(read.chests.first { $0.id == "Farm@1,2" }?.items)
            var wood = woodRead
            wood[0].stack = 77
            try Data(newer.utf8).write(to: info.fileURL)

            #expect(throws: SaveDocument.Failure.changedOnDisk) {
                try manager.writeEdits(info: info, sheet: nil, items: nil,
                                       chests: ["Farm@1,2": SlotEdit.changes(wood, from: woodRead)], expected: nil)
            }
            #expect(try String(contentsOf: info.fileURL, encoding: .utf8) == newer)
            #expect(try backups(of: info) == 0)
        }
    }

    /// Deux coffres \"Input\" sur une tuile (`~2`) ; le premier disparaît : les `id` glissent.
    @Test func aConfirmedOverwriteRefusesAShiftedDuplicateChestId() throws {
        func input(_ name: String, _ id: String) -> String {
            "<Chest xsi:type=\"Chest\"><name>Input</name><items><Item xsi:type=\"Object\"><name>\(name)</name>"
                + "<itemId>\(id)</itemId><stack>4</stack></Item></items></Chest>"
        }
        func mill(_ chest: String) -> String {
            "<Building><buildingType>Mill</buildingType><tileX>7</tileX><tileY>8</tileY>"
                + "<buildingChests>\(chest)</buildingChests></Building>"
        }
        let head = "<?xml version=\"1.0\" encoding=\"utf-8\"?><SaveGame xmlns:xsi=\"x\"><player><name>Jemila</name>"
            + "<items /></player><locations><GameLocation><name>Farm</name><objects /><buildings>"
        let tail = "</buildings></GameLocation></locations></SaveGame>"
        let original = head + mill(input("Hay", "178")) + mill(input("Wheat", "262")) + tail
        let newer = head + mill(input("Wheat", "262")) + tail
        for id in ["Farm@7,8#bc:Input", "Farm@7,8#bc:Input~2"] {
            let env = TestEnvironment()
            defer { env.cleanup() }
            let info = try env.makeSave(named: "Edits_Over_4_\(id.count)", content: original)
            let manager = SaveManager(isGameRunning: { false })
            let read = try #require(manager.fetchContents(for: info))
            let slotsRead = try #require(read.chests.first { $0.id == id }?.items)
            var slots = slotsRead
            slots[0].stack = 1
            try Data(newer.utf8).write(to: info.fileURL)

            // `Input` désigne maintenant le Blé ; `Input~2` n'existe plus.
            #expect(throws: SaveDocument.Failure.changedOnDisk) {
                try manager.writeEdits(info: info, sheet: nil, items: nil,
                                       chests: [id: SlotEdit.changes(slots, from: slotsRead)], expected: nil)
            }
            #expect(try String(contentsOf: info.fileURL, encoding: .utf8) == newer)
        }
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
