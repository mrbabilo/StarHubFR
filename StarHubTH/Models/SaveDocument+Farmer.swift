import Foundation

/// Les champs du fermier et son mariage, modifiés dans l'arbre de la partie
/// (B6-T1). Même portée que les remplacements de texte qu'ils remplacent :
/// `<player>` d'abord, ses enfants **directs** avant tout (un monstre de
/// `<questLog>` porte ses propres `<maxHealth>`, revue H-T5b).
extension SaveDocument {
    /// Index de saison du save = enum `Season` du jeu (mesuré) :
    /// Spring=0, Summer=1, Fall=2, Winter=3.
    private static let seasonsByIndex = ["spring", "summer", "fall", "winter"]

    /// Premier élément `name` sous `node`, en ordre de document, qui ne porte
    /// que du texte (une balise composée n'est pas une valeur).
    static func firstTextElement(named name: String, under node: XMLNode) -> XMLElement? {
        for child in node.children ?? [] {
            guard let element = child as? XMLElement else { continue }
            if element.name == name, !(element.children ?? []).contains(where: { $0 is XMLElement }) { return element }
            if let found = firstTextElement(named: name, under: element) { return found }
        }
        return nil
    }

    /// Enfant direct `name` de `<player>`, sinon le premier plus bas dans
    /// `<player>`, sinon le premier de la partie (`goldenWalnuts` vit hors
    /// du fermier). `false` si la partie ne porte nulle part ce champ.
    @discardableResult
    func setFarmerField(_ name: String, to value: String) -> Bool {
        let direct = player?.elements(forName: name).first {
            !($0.children ?? []).contains(where: { $0 is XMLElement })
        }
        let scoped = direct ?? player.flatMap { Self.firstTextElement(named: name, under: $0) }
        guard let target = scoped ?? Self.firstTextElement(named: name, under: root) else { return false }
        target.stringValue = value   // échappé par la sérialisation
        return true
    }

    /// `<spouse>` du fermier posé, ou retiré quand `name` est vide. Absent :
    /// inséré après `<name>`, faute de quoi rien n'est écrit.
    func setSpouse(_ name: String) {
        guard let player else { return }
        let existing = player.elements(forName: "spouse")
        if name.isEmpty {
            existing.forEach { $0.detach() }
        } else if let spouse = existing.first {
            spouse.stringValue = name
        } else if let nameNode = player.elements(forName: "name").first {
            player.insertChild(XMLElement(name: "spouse", stringValue: name), at: nameNode.index + 1)
        }
    }

    /// L'entrée d'amitié de `npc` chez le fermier : dans `<friendshipData>`
    /// s'il existe, sinon n'importe où dans `<player>`.
    private func friendshipItem(of npc: String) -> XMLElement? {
        guard let player else { return nil }
        let scope: XMLElement = player.elements(forName: "friendshipData").first ?? player
        func search(_ node: XMLElement) -> XMLElement? {
            for child in node.children ?? [] {
                guard let element = child as? XMLElement else { continue }
                if element.name == "item",
                   element.elements(forName: "key").first?.elements(forName: "string").first?.stringValue == npc {
                    return element
                }
                if let found = search(element) { return found }
            }
            return nil
        }
        return search(scope)
    }

    private static func descendants(named name: String, of node: XMLElement) -> [XMLElement] {
        (node.children ?? []).compactMap { $0 as? XMLElement }.flatMap { child in
            (child.name == name ? [child] : []) + descendants(named: name, of: child)
        }
    }

    /// Ancien conjoint : `Married` → `Friendly`, `<WeddingDate>` retirée.
    func demoteSpouse(_ npc: String) {
        guard let item = friendshipItem(of: npc) else { return }
        for status in Self.descendants(named: "Status", of: item) where status.stringValue == "Married" {
            status.stringValue = "Friendly"
        }
        Self.descendants(named: "WeddingDate", of: item).forEach { $0.detach() }
    }

    /// Nouveau conjoint : `Married` et une `<WeddingDate>` à la date courante
    /// du fermier (`WorldDate` : `Year`, `DayOfMonth`, saison **en texte**,
    /// mesuré sur les assemblies 1.6.15). Sans entrée d'amitié : rien inventé.
    func promoteSpouse(_ npc: String) {
        func field(_ name: String) -> String? {
            guard let value = Self.firstTextElement(named: name, under: root)?.stringValue, !value.isEmpty else { return nil }
            return value
        }
        guard let year = field("yearForSaveGame"), let day = field("dayOfMonthForSaveGame"),
              let seasonIndex = field("seasonForSaveGame").flatMap(Int.init),
              Self.seasonsByIndex.indices.contains(seasonIndex),
              let item = friendshipItem(of: npc) else { return }
        let statuses = Self.descendants(named: "Status", of: item)
        statuses.forEach { $0.stringValue = "Married" }
        Self.descendants(named: "WeddingDate", of: item).forEach { $0.detach() }
        guard let status = statuses.first, let parent = status.parent as? XMLElement else { return }
        let date = XMLElement(name: "WeddingDate")
        date.addChild(XMLElement(name: "Year", stringValue: year))
        date.addChild(XMLElement(name: "DayOfMonth", stringValue: day))
        date.addChild(XMLElement(name: "Season", stringValue: Self.seasonsByIndex[seasonIndex]))
        parent.insertChild(date, at: status.index + 1)
    }
}
