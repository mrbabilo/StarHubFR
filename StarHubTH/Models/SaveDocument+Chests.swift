import Foundation

/// Les contenants de la partie (A1) : coffres posés, réfrigérateurs, coffres
/// de bâtiment, inventaires globaux. Lus et écrits dans l'arbre, comme le sac.
extension SaveDocument {
    /// Un contenant et le nœud dont les enfants `<Item>` sont ses cases.
    private struct ChestEntry {
        let chest: SaveChest
        let container: XMLElement?
    }

    /// Types de bâtiments du jeu de base : un coffre d'un autre type vient d'un mod, lu seulement.
    private static let vanillaBuildings: Set<String> = [
        "Coop", "Big Coop", "Deluxe Coop", "Barn", "Big Barn", "Deluxe Barn", "Silo", "Stable", "Well", "Slime Hutch",
        "Shed", "Big Shed", "Cabin", "Stone Cabin", "Plank Cabin", "Log Cabin", "Mill", "Junimo Hut", "Fish Pond",
        "Shipping Bin", "Pet Bowl", "Greenhouse", "Gold Clock", "Farmhouse", "Earth Obelisk", "Water Obelisk",
        "Desert Obelisk", "Island Obelisk",
    ]

    /// Tous les contenants lisibles, dans l'ordre du fichier ; chaque `id` est unique.
    func chests() -> [SaveChest] { chestEntries().map(\.chest) }

    /// Remplace les cases du contenant `id`. `false` — rien changé — si l'`id`
    /// est inconnu ou le contenant en lecture seule.
    func applyChestItems(_ items: [InventoryItem], toChest id: String) -> Bool {
        guard let entry = chestEntries().first(where: { $0.chest.id == id }), entry.chest.isEditable,
              let container = entry.container else { return false }
        Self.apply(items, to: container.elements(forName: "Item"))
        return true
    }

    private func chestEntries() -> [ChestEntry] {
        var entries: [ChestEntry] = []
        var used = Set<String>()
        func add(id base: String, location: String, x: Int, y: Int, name: String, kind: SaveChest.Kind,
                 container: XMLElement?, editable: Bool = true) {
            var id = base
            var suffix = 2
            while used.contains(id) { id = "\(base)~\(suffix)"; suffix += 1 }
            used.insert(id)
            let items = container.map { Self.slots($0.elements(forName: "Item")) } ?? []
            entries.append(ChestEntry(chest: SaveChest(id: id, location: location, tileX: x, tileY: y, name: name, kind: kind,
                                                       items: items, isEditable: editable && container != nil),
                                      container: container))
        }
        func scan(_ place: XMLElement, as location: String) {
            // Seules les valeurs directes de `objects` : un `heldObject` (ruche, cuve…) n'est pas un coffre.
            for entry in place.elements(forName: "objects").first?.elements(forName: "item") ?? [] {
                guard let chest = entry.elements(forName: "value").first?.elements(forName: "Object").first,
                      chest.attribute(forName: "xsi:type")?.stringValue == "Chest" else { continue }
                let tile = Self.tile(of: entry.elements(forName: "key").first?.elements(forName: "Vector2").first)
                add(id: "\(location)@\(tile.x),\(tile.y)", location: location, x: tile.x, y: tile.y,
                    name: chest.elements(forName: "name").first?.stringValue ?? "Chest", kind: .placed,
                    container: chest.elements(forName: "items").first)
            }
            if let fridge = place.elements(forName: "fridge").first {
                add(id: "\(location)#fridge", location: location, x: 0, y: 0, name: "Fridge", kind: .fridge,
                    container: fridge.elements(forName: "items").first)
            }
            for building in place.elements(forName: "buildings").first?.elements(forName: "Building") ?? [] {
                let type = building.elements(forName: "buildingType").first?.stringValue ?? ""
                let x = Int(building.elements(forName: "tileX").first?.stringValue ?? "") ?? 0
                let y = Int(building.elements(forName: "tileY").first?.stringValue ?? "") ?? 0
                for chest in building.elements(forName: "buildingChests").first?.elements(forName: "Chest") ?? [] {
                    let name = chest.elements(forName: "name").first?.stringValue ?? "Chest"
                    add(id: "\(location)@\(x),\(y)#bc:\(name)", location: location, x: x, y: y, name: name,
                        kind: .buildingChest(building: type, chest: name), container: chest.elements(forName: "items").first,
                        editable: Self.vanillaBuildings.contains(type))
                }
                if let indoors = building.elements(forName: "indoors").first {
                    let inside = indoors.elements(forName: "uniqueName").first?.stringValue
                        ?? indoors.elements(forName: "name").first?.stringValue ?? ""
                    if !inside.isEmpty { scan(indoors, as: inside) }
                }
            }
        }
        for place in root.elements(forName: "locations").first?.elements(forName: "GameLocation") ?? [] {
            let name = place.elements(forName: "uniqueName").first?.stringValue
                ?? place.elements(forName: "name").first?.stringValue ?? ""
            scan(place, as: name)
        }
        for entry in root.elements(forName: "globalInventories").first?.elements(forName: "item") ?? [] {
            guard let key = entry.elements(forName: "key").first?.elements(forName: "string").first?.stringValue else { continue }
            let junimo = key == "JunimoChests"
            add(id: "global:\(key)", location: "", x: 0, y: 0, name: key, kind: junimo ? .junimo : .modInventory(key: key),
                container: entry.elements(forName: "value").first?.elements(forName: "ArrayOfItem").first, editable: junimo)
        }
        return entries
    }

    private static func tile(of vector: XMLElement?) -> (x: Int, y: Int) {
        func value(_ name: String) -> Int { Int(vector?.elements(forName: name).first?.stringValue ?? "") ?? 0 }
        return (value("X"), value("Y"))
    }
}
