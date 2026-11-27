import Foundation

struct InventoryItem: Identifiable, Equatable {
    let id = UUID()
    var slotIndex: Int
    var itemId: String
    var name: String
    var stack: Int
    var isObject: Bool
    /// `<bigCraftable>` : un Coffre `130` rangé n'est pas le Thon `(O)130`.
    var isBigCraftable: Bool = false

    // For empty slots
    static func empty(slot: Int) -> InventoryItem {
        InventoryItem(slotIndex: slot, itemId: "", name: "", stack: 0, isObject: false)
    }
}
