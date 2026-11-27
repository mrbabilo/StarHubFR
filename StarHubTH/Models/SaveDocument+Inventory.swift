import Foundation

/// Le sac du fermier principal, lu et modifié dans l'arbre de la partie
/// (`<SaveGame>/<player>/<items>`, une case par `<Item>`).
extension SaveDocument {
    private var itemNodes: [XMLElement]? {
        player?.elements(forName: "items").first?.elements(forName: "Item")
    }

    /// Les cases du sac, `nil` si la partie n'en porte pas.
    func inventory() -> [InventoryItem]? {
        guard let nodes = itemNodes else { return nil }
        return nodes.enumerated().map { index, node in
            let xsiType = node.attribute(forName: "xsi:type")?.stringValue ?? ""
            func child(_ name: String) -> String? { node.elements(forName: name).first?.stringValue }
            if xsiType == "Object" {
                return InventoryItem(slotIndex: index, itemId: child("itemId") ?? "Unknown", name: child("name") ?? "Unknown",
                                     stack: Int(child("stack") ?? "1") ?? 1, isObject: true)
            }
            if node.attribute(forName: "xsi:nil")?.stringValue == "true" { return InventoryItem.empty(slot: index) }
            // Armes, anneaux… : nom affiché seulement, jamais réécrits.
            let name = child("name") ?? xsiType
            let displayName = name.isEmpty ? (xsiType.isEmpty ? "Unknown Item" : xsiType) : name
            return InventoryItem(slotIndex: index, itemId: child("itemId") ?? "", name: displayName, stack: 1, isObject: false)
        }
    }

    /// Pose les cases données dans l'arbre : quantité et identifiant d'un objet,
    /// case vidée pour un objet sans nom. `false` si la partie n'a pas de sac.
    func applyInventory(_ items: [InventoryItem]) -> Bool {
        guard let nodes = itemNodes else { return false }
        for item in items where nodes.indices.contains(item.slotIndex) {
            let node = nodes[item.slotIndex]
            if item.isObject {
                if let stack = node.elements(forName: "stack").first {
                    stack.stringValue = "\(item.stack)"
                } else {
                    node.addChild(XMLElement(name: "stack", stringValue: "\(item.stack)"))
                }
                node.elements(forName: "itemId").first?.stringValue = item.itemId
            } else if item.name.isEmpty {
                node.setChildren(nil)
                if let empty = XMLNode.attribute(withName: "xsi:nil", stringValue: "true") as? XMLNode {
                    node.attributes = [empty]
                }
            }
        }
        return true
    }
}
