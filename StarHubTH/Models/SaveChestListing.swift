import Foundation

/// Les coffres d'une partie rangés par lieu, pour l'écran « Coffres » (A2).
struct SaveChestGroup: Identifiable, Equatable, Sendable {
    /// Le lieu ; vide pour les inventaires globaux (Junimos, mods).
    let location: String
    let chests: [SaveChest]
    var id: String { location }
}

enum SaveChestListing {
    /// Les coffres par lieu, dans l'ordre de la partie, les inventaires globaux en dernier.
    /// `query` : un morceau de nom d'objet, sans égard à la casse ni aux accents ;
    /// ne restent que les coffres qui le contiennent. Vide = tout. `name` : le nom
    /// cherché, celui que la vue montre (B4 : le nom du jeu, `SaveEditSession.displayName`).
    static func groups(_ chests: [SaveChest], matching query: String = "",
                       name: (InventoryItem) -> String = \.name) -> [SaveChestGroup] {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        var order: [String] = []
        var byLocation: [String: [SaveChest]] = [:]
        for chest in chests where needle.isEmpty || chest.items.contains(where: { fold(name($0)).contains(needle) }) {
            if byLocation[chest.location] == nil { order.append(chest.location) }
            byLocation[chest.location, default: []].append(chest)
        }
        let sorted = order.filter { !$0.isEmpty } + order.filter(\.isEmpty)
        return sorted.map { SaveChestGroup(location: $0, chests: byLocation[$0] ?? []) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

extension SaveChest {
    /// Les mots que la vue fournit déjà traduits.
    struct Labels: Equatable, Sendable {
        let chest: String
        let fridge: String
        let junimo: String
    }

    /// Le nom montré : le nom de la partie quand il dit quelque chose, sinon le libellé du type.
    func displayName(_ labels: Labels) -> String {
        switch kind {
        case .placed: name.isEmpty || name == "Chest" ? labels.chest : name
        case .fridge: labels.fridge
        case .junimo: labels.junimo
        case .buildingChest(let building, let chest): "\(building) · \(chest.isEmpty || chest == "Chest" ? labels.chest : chest)"
        case .modInventory(let key): key
        }
    }

    /// Le libellé d'un contenant en lecture seule : inventaire de mod, ou contenant non modifiable.
    var readOnlyKey: String {
        if case .modInventory = kind { return L10n.Saves.chestReadOnly }
        return L10n.Saves.chestNotEditable
    }

    /// Nombre de cases du contenant.
    var slotCount: Int { items.count }
    /// Cases qui portent un objet.
    var occupiedCount: Int { items.filter { !$0.name.isEmpty }.count }
}
