import Foundation
import Testing
@testable import StarHubTHCore

/// **A1 — lire les coffres.** Coffres posés, réfrigérateurs, coffres de
/// bâtiment et inventaires globaux d'une partie, avec un `id` stable et unique.
@Suite struct SaveChestsTests {
    private static func item(_ name: String, id: String, stack: Int, bigCraftable: Bool = false) -> String {
        "<Item xsi:type=\"Object\"><name>\(name)</name><itemId>\(id)</itemId><stack>\(stack)</stack><bigCraftable>\(bigCraftable)</bigCraftable></Item>"
    }

    private static func chest(_ name: String, x: Int, y: Int, items: String = "", tag: String = "Object") -> String {
        "<\(tag) xsi:type=\"Chest\"><name>\(name)</name><tileLocation><X>\(x)</X><Y>\(y)</Y></tileLocation><items>\(items)</items></\(tag)>"
    }

    private static func placed(_ chest: String, x: Int, y: Int) -> String {
        "<item><key><Vector2><X>\(x)</X><Y>\(y)</Y></Vector2></key><value>\(chest)</value></item>"
    }

    private static func building(_ type: String, x: Int, y: Int, chests: [String] = [], indoors: String = "") -> String {
        let held = chests.isEmpty ? "" : "<buildingChests>\(chests.joined())</buildingChests>"
        return "<Building><buildingType>\(type)</buildingType><tileX>\(x)</tileX><tileY>\(y)</tileY>\(held)\(indoors)</Building>"
    }

    private static let sixty = (0..<60).map { $0 % 2 == 0 ? item("Parsnip", id: "24", stack: $0 + 1) : "<Item xsi:nil=\"true\" />" }.joined()

    private static let xml = """
        <?xml version="1.0" encoding="utf-8"?><SaveGame xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
        <player><name>Jemila</name><items>\(item("Parsnip", id: "24", stack: 3))</items></player>\
        <locations>\
        <GameLocation xsi:type="Farm"><name>Farm</name><objects>\
        \(placed(chest("Chest", x: 10, y: 20, items: item("Coffre", id: "130", stack: 1, bigCraftable: true) + item("Thon", id: "130", stack: 2)), x: 10, y: 20))\
        <item><key><Vector2><X>3</X><Y>4</Y></Vector2></key><value><Object xsi:type="Object"><name>Bee House</name>\
        \(chest("Chest", x: 3, y: 4, tag: "heldObject"))</Object></value></item>\
        </objects><buildings>\
        \(building("Mill", x: 7, y: 8, chests: [chest("Input", x: 0, y: 0, tag: "Chest"), chest("Output", x: 0, y: 0, tag: "Chest")]))\
        \(building("Mod.Office", x: 7, y: 8, chests: [chest("Mod.Office_Input", x: 0, y: 0, tag: "Chest")]))\
        \(building("Coop", x: 20, y: 21, indoors: "<indoors xsi:type=\"Coop\"><name>Coop</name><uniqueName>Coop-1234</uniqueName><objects>\(placed(chest("Chest", x: 1, y: 1, items: item("Egg", id: "176", stack: 5)), x: 1, y: 1))</objects></indoors>"))\
        </buildings></GameLocation>\
        <GameLocation xsi:type="FarmHouse"><name>FarmHouse</name><objects /><fridge xsi:type="Chest"><name>Fridge</name><items>\(item("Milk", id: "184", stack: 4))</items></fridge></GameLocation>\
        <GameLocation><name>BigRoom</name><objects>\(placed(chest("Big Chest", x: 2, y: 2, items: sixty), x: 2, y: 2))</objects></GameLocation>\
        </locations>\
        <globalInventories>\
        <item><key><string>JunimoChests</string></key><value><ArrayOfItem>\(item("Parsnip", id: "24", stack: 7))</ArrayOfItem></value></item>\
        <item><key><string>Mod.Thing.temp</string></key><value><ArrayOfItem>\(item("Mushroom", id: "MOD_1", stack: 2))</ArrayOfItem></value></item>\
        </globalInventories></SaveGame>
        """

    private func document() throws -> SaveDocument {
        let env = TestEnvironment()
        defer { env.cleanup() }
        let info = try env.makeSave(named: "A1_\(UUID().uuidString)", content: Self.xml)
        return try SaveDocument(contentsOf: info.fileURL)
    }

    @Test func placedChestsAreDirectValuesOfObjectsOnly() throws {
        let placed = try document().chests().filter { $0.kind == .placed }
        // Le coffre sous la ruche (`heldObject`) n'en est pas un.
        #expect(placed.map(\.id) == ["Farm@10,20", "Coop-1234@1,1", "BigRoom@2,2"])
        #expect(placed[0].items.map(\.isBigCraftable) == [true, false])
        #expect(placed[0].isEditable)
    }

    @Test func buildingChestsAndFridgesAreFound() throws {
        let chests = try document().chests()
        #expect(chests.filter { $0.kind == .fridge }.map(\.id) == ["FarmHouse#fridge"])
        #expect(chests.first { $0.kind == .fridge }?.items.first?.name == "Milk")
        let building = chests.filter { if case .buildingChest = $0.kind { true } else { false } }
        #expect(building.count == 3)
        #expect(building.first?.kind == .buildingChest(building: "Mill", chest: "Input"))
        #expect(building.first?.tileX == 7 && building.first?.tileY == 8)
    }

    @Test func indoorsUseTheirUniqueName() throws {
        let coop = try #require(try document().chests().first { $0.id == "Coop-1234@1,1" })
        #expect(coop.location == "Coop-1234")
    }

    @Test func noTwoChestsShareAnId() throws {
        let ids = try document().chests().map(\.id)
        #expect(Set(ids).count == ids.count)
        // Deux coffres de bâtiments différents sur la même tuile : ids distincts.
        #expect(ids.contains("Farm@7,8#bc:Input") && ids.contains("Farm@7,8#bc:Mod.Office_Input"))
    }

    @Test func chestItemsFollowTheRealSlotCount() throws {
        let big = try #require(try document().chests().first { $0.id == "BigRoom@2,2" })
        #expect(big.items.count == 60)
        #expect(big.items[1].name.isEmpty && big.items[2].stack == 3)
    }

    @Test func modInventoriesAreReadOnlyButJunimoIsNot() throws {
        let chests = try document().chests()
        let junimo = try #require(chests.first { $0.id == "global:JunimoChests" })
        #expect(junimo.kind == .junimo && junimo.isEditable && junimo.items.first?.stack == 7)
        let mod = try #require(chests.first { $0.id == "global:Mod.Thing.temp" })
        #expect(mod.kind == .modInventory(key: "Mod.Thing.temp") && !mod.isEditable)
        // Coffre d'un bâtiment de mod : lu seulement ; celui du Moulin : éditable.
        #expect(chests.first { $0.id == "Farm@7,8#bc:Mod.Office_Input" }?.isEditable == false)
        #expect(chests.first { $0.id == "Farm@7,8#bc:Input" }?.isEditable == true)
    }

    @Test func applyChestItemsChangesOnlyThatChest() throws {
        let save = try document()
        let before = save.chests()
        var items = try #require(before.first { $0.id == "Farm@10,20" }?.items)
        items[1].stack = 9
        #expect(save.applyChestItems(items, toChest: "Farm@10,20"))
        let after = save.chests()
        #expect(after.first { $0.id == "Farm@10,20" }?.items[1].stack == 9)
        // `InventoryItem` porte un `UUID` par lecture : on compare le contenu.
        func content(_ chest: SaveChest?) -> [String] {
            chest?.items.map { "\($0.slotIndex)|\($0.itemId)|\($0.name)|\($0.stack)" } ?? []
        }
        for chest in before where chest.id != "Farm@10,20" {
            #expect(content(after.first { $0.id == chest.id }) == content(chest))
        }
        #expect(save.inventory()?.first?.stack == 3)
    }

    @Test func applyChestItemsRefusesReadOnly() throws {
        let save = try document()
        let items = try #require(save.chests().first { $0.id == "global:Mod.Thing.temp" }?.items)
        var edited = items
        edited[0].stack = 99
        #expect(!save.applyChestItems(edited, toChest: "global:Mod.Thing.temp"))
        #expect(!save.applyChestItems(edited, toChest: "Nowhere@1,1"))
        #expect(save.chests().first { $0.id == "global:Mod.Thing.temp" }?.items.first?.stack == 2)
    }
}
