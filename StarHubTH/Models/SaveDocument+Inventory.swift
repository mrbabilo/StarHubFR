import Foundation

/// Le sac du fermier principal, lu et modifié dans l'arbre de la partie
/// (`<SaveGame>/<player>/<items>`, une case par `<Item>`). Les coffres
/// (`SaveDocument+Chests`) réutilisent la lecture et l'écriture d'une liste de cases.
extension SaveDocument {
    private var itemNodes: [XMLElement]? {
        player?.elements(forName: "items").first?.elements(forName: "Item")
    }

    /// Les cases du sac, `nil` si la partie n'en porte pas.
    func inventory() -> [InventoryItem]? {
        itemNodes.map(Self.slots)
    }

    /// Pose les cases modifiées du sac et des coffres (`id` → cases), tout ou rien. Chaque case doit
    /// encore porter l'objet lu (`holdsSameItem`) — sinon, ou si un coffre lu a disparu, la partie a
    /// changé depuis la lecture : `.changedOnDisk`, même après un écrasement confirmé. Pas de sac,
    /// coffre en lecture seule : `.malformed`. Rien n'est posé tant que tout n'est pas vérifié.
    func applySlots(bag: [SlotEdit]?, chests: [String: [SlotEdit]]?) throws(Failure) {
        var targets: [(edits: [SlotEdit], nodes: [XMLElement])] = []
        if let bag {
            guard let nodes = itemNodes else { throw .malformed }
            targets.append((bag, nodes))
        }
        if let chests { targets += try chestTargets(chests) }
        for target in targets {
            let now = Self.slots(target.nodes)
            for edit in target.edits {
                guard now.indices.contains(edit.read.slotIndex), now[edit.read.slotIndex].holdsSameItem(as: edit.read)
                else { throw .changedOnDisk }
            }
        }
        for target in targets { Self.apply(target.edits.map(\.edited), to: target.nodes) }
    }

    /// Une case par nœud `<Item>` (`<items>` d'un sac ou d'un coffre, `ArrayOfItem` d'un inventaire global).
    static func slots(_ nodes: [XMLElement]) -> [InventoryItem] {
        nodes.enumerated().map { index, node in
            let xsiType = node.attribute(forName: "xsi:type")?.stringValue ?? ""
            func child(_ name: String) -> String? { node.elements(forName: name).first?.stringValue }
            let bigCraftable = child("bigCraftable") == "true"
            if xsiType == "Object" {
                return InventoryItem(slotIndex: index, itemId: child("itemId") ?? "Unknown", name: child("name") ?? "Unknown",
                                     stack: Int(child("stack") ?? "1") ?? 1, isObject: true, isBigCraftable: bigCraftable)
            }
            if node.attribute(forName: "xsi:nil")?.stringValue == "true" { return InventoryItem.empty(slot: index) }
            // Armes, anneaux… : nom affiché seulement, jamais réécrits.
            let name = child("name") ?? xsiType
            let displayName = name.isEmpty ? (xsiType.isEmpty ? "Unknown Item" : xsiType) : name
            return InventoryItem(slotIndex: index, itemId: child("itemId") ?? "", name: displayName, stack: 1,
                                 isObject: false, isBigCraftable: bigCraftable)
        }
    }

    static func apply(_ items: [InventoryItem], to nodes: [XMLElement]) {
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
    }
}
