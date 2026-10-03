import Foundation

/// Le classement d'une feuille de config : raccourci, valeur illisible, ou
/// rien (règles R1 à R3 et nom d'action), puis les écarts par mod : le
/// catalogue (R4) et le remap des contrôles du jeu. Logique pure, sous
/// `swift test`.
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

    /// R4 — le catalogue (constat utilisateur, tâche 6, mesuré sur
    /// `ModShortcutReferenceHub`, ZeroXPatch) : ce mod *documente* les
    /// raccourcis des autres, il n'en lie aucun. Rien ne distingue son
    /// tableau `Shortcuts` d'un vrai raccourci à `classify(leaf:)` — le
    /// chemin porte « key » et « shortcut », chaque lettre parse — donc la
    /// règle ne peut pas vivre dans `classify`, feuille par feuille : il
    /// faut voir combien de combos *distincts* une même forme de chemin
    /// porte, à l'intérieur d'un même mod.
    ///
    /// Mesure sur les 92 mods actifs du parc réel (142 formes) : le maximum
    /// légitime observé est 2 (une alternative dans un seul champ, ex.
    /// `"A, MouseLeft"`) ; le catalogue est à 42. Seuil retenu : 8 — 4× le
    /// maximum légitime, 5× sous le catalogue. Aucun `UniqueID` en dur.
    static let catalogThreshold = 8

    /// C4-T9 — les UniqueID des mods dont le **métier** est de réécrire les
    /// réglages du jeu, contrôles compris (le même choix que
    /// `IsVanillaControlRemapMod()` de ModernConfigMenu 2.1.1, qui a relevé
    /// le cas). Leur signal « conflit jeu » est un faux positif qui gonfle
    /// `problemCount` ; leurs collisions avec d'autres mods restent réelles.
    /// Figé sur la mesure du parc (sonde du 2026-09-15 : un seul mod, une
    /// seule ligne) — SMAPI compare les UniqueID sans la casse, ici pareil.
    /// Une heuristique de nom écartait des mods légitimes : sur trois
    /// candidats au mot « remap », deux sont des cartes.
    ///
    /// Source MCM relue (décompilation `ikdasm` de la DLL 2.1.2 installée) :
    /// leur détection n'est pas une liste mais trois sous-chaînes sans la
    /// casse — `GlobalConfigSettings` dans l'UniqueID, `Global Config
    /// Settings` dans le nom, `GameControls` dans l'UniqueID. Passées sur le
    /// parc, elles n'attrapent que GCSR : nos deux approches sont
    /// équivalentes ici, et la liste exacte ne peut pas écarter un mod
    /// légitime par accident.
    static let vanillaRemapModIds: Set<String> = [
        "fawazt.globalconfigsettingsrewrite",
    ]

    /// La forme d'un `keyPath` : chaque indice de tableau réduit à `[]`
    /// (`["Shortcuts", "[7]", "KeyCombo"]` → `"Shortcuts.[].KeyCombo"`).
    static func pathShape(_ keyPath: [String]) -> String {
        keyPath.map { segment in
            segment.range(of: #"^\[\d+\]$"#, options: .regularExpression) != nil ? "[]" : segment
        }.joined(separator: ".")
    }

    /// Les formes de chemin d'un fichier qui sont des catalogues (R4) :
    /// plus de `catalogThreshold` combinaisons distinctes sous la même
    /// forme. **C4-T10** — l'éditeur de config l'emploie pour ne pas poser
    /// de contrôle de capture sur un mod qui *documente* les raccourcis des
    /// autres sans en lier aucun (`ModShortcutReferenceHub`) ; `report`
    /// l'emploie pour le même écart, côté rapport.
    public static func catalogShapes(of leaves: [ConfigEditorModel.Leaf]) -> Set<String> {
        var keybindLeaves: [(keyPath: [String], combos: [KeybindCombo])] = []
        for leaf in leaves {
            if case .keybind(let combos) = classify(leaf: leaf) {
                keybindLeaves.append((leaf.keyPath, combos))
            }
        }
        return catalogShapes(fromClassified: keybindLeaves)
    }

    /// Passe 2 de la règle R4, partagée : par forme de chemin, compter les
    /// combos distincts — au-delà du seuil, la forme est un catalogue, elle
    /// ne produit aucune liaison. Compté par mod, jamais cumulé entre mods :
    /// deux mods qui déclarent chacun peu de touches sous une forme de même
    /// nom ne s'additionnent pas.
    static func catalogShapes(
        fromClassified keybindLeaves: [(keyPath: [String], combos: [KeybindCombo])]) -> Set<String> {
        var combosByShape: [String: Set<KeybindCombo>] = [:]
        for (keyPath, combos) in keybindLeaves {
            let shape = pathShape(keyPath)
            for combo in combos where !combo.isEmpty {
                combosByShape[shape, default: []].insert(combo)
            }
        }
        return Set(combosByShape.filter { $0.value.count > catalogThreshold }.map(\.key))
    }
}
