import Foundation

/// C4-T18 — ce que la sonde dit des valeurs par défaut d'un mod. Elles viennent
/// d'une config neuve, comme celle que SMAPI crée quand le fichier manque.
extension GmcmModOptions {
    /// La config neuve, par chemin de clé en minuscules.
    static func defaults(from json: String?) -> [[String]: ConfigJSONTree.Value] {
        guard let json, let tree = ConfigJSONTree.parse(json) else { return [:] }
        var values: [[String]: ConfigJSONTree.Value] = [:]
        for leaf in ConfigEditorModel.leaves(of: tree) {
            values[leaf.keyPath.map { $0.lowercased() }] = leaf.value
        }
        return values
    }

    /// Le contrôle qui remettrait le défaut, `nil` sans défaut connu, quand la
    /// valeur n'en diffère pas, ou quand le type changerait.
    func defaultControl(of leaf: ConfigEditorModel.Leaf,
                        shownAs control: ConfigEditorModel.Control) -> ConfigEditorModel.Control? {
        guard let value = defaults[leaf.keyPath.map { $0.lowercased() }],
              !Self.isSame(value, leaf.value) else { return nil }
        switch (value, leaf.value) {
        case (.bool, .bool), (.number, .number), (.string, .string): break
        default: return nil
        }
        if case .choice(_, let among) = control {
            guard let literal = ConfigEditorModel.literalText(of: value),
                  let spelling = among.first(where: { $0.lowercased() == literal.lowercased() }) else { return nil }
            return .choice(selected: spelling, among: among)
        }
        return ConfigEditorModel.control(for: value)
    }

    /// `1.50` vaut `1.5`, et SMAPI lit `both` comme `Both`.
    private static func isSame(_ a: ConfigJSONTree.Value, _ b: ConfigJSONTree.Value) -> Bool {
        switch (a, b) {
        case (.number(let x), .number(let y)):
            return ConfigEditorModel.doubleValue(ofLiteral: x) == ConfigEditorModel.doubleValue(ofLiteral: y)
        case (.string(let x), .string(let y)):
            return x.lowercased() == y.lowercased()
        default:
            return a == b
        }
    }
}
