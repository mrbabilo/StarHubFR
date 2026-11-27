import Foundation

/// Un contenant de la partie dont on peut lire (et plus tard modifier) les cases : coffre posé,
/// réfrigérateur, coffre de bâtiment ou inventaire global (A1).
struct SaveChest: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case placed
        case fridge
        case buildingChest(building: String, chest: String)
        /// `globalInventories` « JunimoChests » : éditable.
        case junimo
        /// Inventaire global d'un mod : lu, jamais écrit.
        case modInventory(key: String)
    }

    /// `<lieu>@x,y`, `<lieu>#fridge`, `<lieu>@x,y#bc:<coffre>` ou `global:<clé>`.
    let id: String
    let location: String
    let tileX: Int
    let tileY: Int
    let name: String
    let kind: Kind
    let items: [InventoryItem]
    let isEditable: Bool
}
