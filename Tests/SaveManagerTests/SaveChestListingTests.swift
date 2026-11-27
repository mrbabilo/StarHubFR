import Foundation
import Testing
@testable import StarHubTHCore

/// **A2 — l'écran des coffres** : regroupement par lieu, recherche, noms montrés.
@Suite struct SaveChestListingTests {
    private static let labels = SaveChest.Labels(chest: "Coffre", fridge: "Frigo", junimo: "Junimos")

    private static func item(_ name: String, slot: Int = 0) -> InventoryItem {
        InventoryItem(slotIndex: slot, itemId: "1", name: name, stack: 2, isObject: true)
    }

    private static func make(_ id: String, in location: String, name: String = "Chest", kind: SaveChest.Kind = .placed,
                              items: [InventoryItem] = []) -> SaveChest {
        SaveChest(id: id, location: location, tileX: 0, tileY: 0, name: name, kind: kind, items: items, isEditable: true)
    }

    @Test func groupsFollowTheSaveAndSharedInventoriesComeLast() {
        let chests = [Self.make("g", in: "", name: "Mod", kind: .modInventory(key: "Mod")),
                      Self.make("a", in: "Farm"), Self.make("b", in: "FarmHouse"), Self.make("c", in: "Farm")]
        let groups = SaveChestListing.groups(chests)
        #expect(groups.map(\.location) == ["Farm", "FarmHouse", ""])
        #expect(groups[0].chests.map(\.id) == ["a", "c"])
    }

    @Test func searchKeepsChestsHoldingTheItemIgnoringCaseAndAccents() {
        let chests = [Self.make("a", in: "Farm", items: [Self.item("Bois")]),
                      Self.make("b", in: "Farm", items: [Self.item("Pierre")]),
                      Self.make("c", in: "Shed", items: [Self.item("Café")])]
        #expect(SaveChestListing.groups(chests, matching: " BOIS ").flatMap(\.chests).map(\.id) == ["a"])
        #expect(SaveChestListing.groups(chests, matching: "cafe").map(\.location) == ["Shed"])
        #expect(SaveChestListing.groups(chests, matching: "zzz").isEmpty)
        #expect(SaveChestListing.groups(chests, matching: "").flatMap(\.chests).count == 3)
    }

    @Test func displayNamesFollowTheKind() {
        let labels = Self.labels
        #expect(Self.make("a", in: "Farm").displayName(labels) == "Coffre")
        #expect(Self.make("a", in: "Farm", name: "Stockage").displayName(labels) == "Stockage")
        #expect(Self.make("f", in: "FarmHouse", kind: .fridge).displayName(labels) == "Frigo")
        #expect(Self.make("j", in: "", kind: .junimo).displayName(labels) == "Junimos")
        #expect(Self.make("m", in: "", kind: .modInventory(key: "Author.Mod")).displayName(labels) == "Author.Mod")
        #expect(Self.make("b", in: "Farm", kind: .buildingChest(building: "Mill", chest: "Output")).displayName(labels) == "Mill · Output")
    }

    @Test func readOnlyLabelFollowsTheKind() {
        #expect(Self.make("m", in: "", kind: .modInventory(key: "M")).readOnlyKey == L10n.Saves.chestReadOnly)
        #expect(Self.make("b", in: "Farm", kind: .buildingChest(building: "Mod.Office", chest: "In")).readOnlyKey == L10n.Saves.chestNotEditable)
    }

    @Test func slotCountsSeparateOccupiedFromEmpty() {
        let held = Self.make("a", in: "Farm", items: [Self.item("Bois"), .empty(slot: 1), Self.item("Pierre", slot: 2)])
        #expect(held.slotCount == 3)
        #expect(held.occupiedCount == 2)
    }
}
