import Foundation

/// Le classement d'une feuille de config : raccourci, valeur illisible, ou
/// rien (règles R1 à R3 et nom d'action). Logique pure, sous `swift test`.
extension KeybindScanner {
    /// R1/R2/R3 — la règle gelée par la mesure (spec §6 + son constat) :
    /// sans indice de nom, une origine numérique (entier JSON, chaîne
    /// numérique, liste numérique — le cas CollectionsMod mesuré) n'est
    /// jamais un raccourci ; un champ nommé illisible n'entre dans
    /// `unrecognized` qu'avec un jeton reconnaissable.
    public static func classify(leaf: ConfigEditorModel.Leaf) -> Decision {
        let hinted = leaf.keyPath.joined(separator: ".").range(
            of: "key|bind|shortcut", options: [.regularExpression, .caseInsensitive]) != nil
        let parsed = KeybindParser.parse(leaf.value)
        if hinted {
            if let combos = parsed { return .keybind(combos) }
            return hasRecognizableToken(leaf.value)
                ? .unrecognized(raw: literal(of: leaf.value)) : .notKeybind
        }
        // Sous un nom d'action, une lettre seule suffit (2026-10-03 : C de
        // Chests Anywhere, E/M/ZQSD de GCSR manquaient au clavier) ; le garde
        // numérique tient toujours (`ButtonOffsetX = 0`).
        let single = actionNamed(leaf.keyPath)
        guard let combos = parsed, !isNumericOrigin(leaf.value),
              combos.contains(where: { single ? !$0.isEmpty : $0.isDistinctive })
        else { return .notKeybind }
        return .keybind(combos)
    }

    /// Un nom d'action (`Controls.Toggle`, `AccessMenu`, `MoveUp`,
    /// `Input.PauseResume`), hors réglages de manette — Item Bags y écrit
    /// les boutons XNA `A`, `X`, qui ne sont pas des touches clavier.
    /// Mesuré sur le parc : 18 raccourcis rattrapés, aucun faux
    /// (`ClothesColorGirl = A`, `SecondarySortingPriority = Y` restent dehors).
    static func actionNamed(_ keyPath: [String]) -> Bool {
        let path = keyPath.joined(separator: ".")
        return path.range(of: "control|input|toggle|button|action|access|move|cycle|open",
                          options: [.regularExpression, .caseInsensitive]) != nil
            && path.range(of: "gamepad|controller", options: [.regularExpression, .caseInsensitive]) == nil
    }

    /// Origine numérique (règle gelée) : entier JSON, chaîne numérique,
    /// ou liste dont tous les éléments le sont.
    static func isNumericOrigin(_ value: ConfigJSONTree.Value) -> Bool {
        switch value {
        case .number: return true
        case .string(let s):
            return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
        case .array(let items):
            guard !items.isEmpty else { return true }
            return items.allSatisfy { isNumericOrigin($0) }
        default: return false
        }
    }

    /// Au moins un jeton reconnaissable : nom `SButton` (casse-insensible)
    /// ou modificateur nu — les typos que le `TryParse` de SMAPI rejette.
    static func hasRecognizableToken(_ value: ConfigJSONTree.Value) -> Bool {
        let texts: [String]
        switch value {
        case .string(let s): texts = [s]
        case .array(let items):
            texts = items.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        default: return false
        }
        return texts.contains { text in
            text.split(whereSeparator: { "+, ".contains($0) }).contains { token in
                SButtonTable.canonicalName(for: String(token)) != nil
                    || ["shift", "ctrl", "alt"].contains(token.lowercased())
            }
        }
    }

    static func literal(of value: ConfigJSONTree.Value) -> String {
        if case .string(let s) = value { return s }
        if case .number(let lit) = value { return lit }
        return "?"
    }
}
