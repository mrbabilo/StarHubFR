import Foundation

/// Les contrôles du jeu et leurs boutons **par défaut**, figés du relevé IL
/// du constructeur `StardewValley.Options` (tâche 0, step 3). Ce ne sont pas
/// les contrôles réels de l'utilisateur — la réserve est affichée à l'écran.
public enum GameControlDefaults {
    public struct GameControl: Equatable, Sendable {
        public let name: String
        public let buttons: [String]
        public init(name: String, buttons: [String]) { self.name = name; self.buttons = buttons }
    }
    /// ── coller le relevé de la tâche 0 (step 3) : un `GameControl` par
    /// champ `InputButton[]` du constructeur d'`Options`, tous. ──
    public static let controls: [GameControl] = [
        GameControl(name: "moveUpButton", buttons: ["W"]),
        GameControl(name: "moveDownButton", buttons: ["S"]),
        GameControl(name: "moveLeftButton", buttons: ["A"]),
        GameControl(name: "moveRightButton", buttons: ["D"]),
        GameControl(name: "actionButton", buttons: ["X", "MouseRight"]),
        GameControl(name: "cancelButton", buttons: ["V"]),
        GameControl(name: "useToolButton", buttons: ["C", "MouseLeft"]),
        GameControl(name: "menuButton", buttons: ["E", "Escape"]),
        GameControl(name: "runButton", buttons: ["LeftShift"]),
        GameControl(name: "chatButton", buttons: ["T", "OemQuestion"]),
        GameControl(name: "mapButton", buttons: ["M"]),
        GameControl(name: "journalButton", buttons: ["F"]),
        GameControl(name: "inventorySlot1", buttons: ["D1"]),
        GameControl(name: "inventorySlot2", buttons: ["D2"]),
        GameControl(name: "inventorySlot3", buttons: ["D3"]),
        GameControl(name: "inventorySlot4", buttons: ["D4"]),
        GameControl(name: "inventorySlot5", buttons: ["D5"]),
        GameControl(name: "inventorySlot6", buttons: ["D6"]),
        GameControl(name: "inventorySlot7", buttons: ["D7"]),
        GameControl(name: "inventorySlot8", buttons: ["D8"]),
        GameControl(name: "inventorySlot9", buttons: ["D9"]),
        GameControl(name: "inventorySlot10", buttons: ["D0"]),
        GameControl(name: "inventorySlot11", buttons: ["OemMinus"]),
        GameControl(name: "inventorySlot12", buttons: ["OemPlus"]),
        GameControl(name: "toolbarSwap", buttons: ["Tab"]),
        GameControl(name: "emoteButton", buttons: ["Y"]),
    ]
}

public enum KeybindScanner {

    public struct ModScan: Sendable {
        public let id: String
        public let name: String
        public let isActive: Bool
        public let tree: ConfigJSONTree.Value
        public init(id: String, name: String, isActive: Bool, tree: ConfigJSONTree.Value) {
            self.id = id; self.name = name; self.isActive = isActive; self.tree = tree
        }
    }

    public enum Decision: Equatable, Sendable {
        case keybind([KeybindCombo])
        case unrecognized(raw: String)
        case notKeybind
    }

    public struct ModUse: Hashable, Sendable {
        public let modID: String
        public let modName: String
        public let keyPath: [String]
    }
    public struct KeybindCollision: Equatable, Sendable {
        public let combo: KeybindCombo
        public let uses: [ModUse]
    }
    public struct GameControlConflict: Equatable, Sendable {
        public let control: GameControlDefaults.GameControl
        public let uses: [ModUse]
    }
    public struct UnrecognizedKeybind: Hashable, Sendable {
        public let modID: String, modName: String, keyPath: [String], raw: String
    }
    public struct KeybindReport: Equatable, Sendable {
        public var collisions: [KeybindCollision]
        public var gameConflicts: [GameControlConflict]
        public var unrecognized: [UnrecognizedKeybind]
        public var scannedMods: Int
        public var keybindCount: Int
        public var pausedIgnored: Int
    }

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
        guard let combos = parsed, !isNumericOrigin(leaf.value),
              combos.contains(where: \.isDistinctive) else { return .notKeybind }
        return .keybind(combos)
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

    public static func report(mods: [ModScan]) -> KeybindReport {
        var index: [KeybindCombo: [ModUse]] = [:]
        var gameIndex: [String: [ModUse]] = [:]      // nom de contrôle → usages
        var unrecognized: [UnrecognizedKeybind] = []
        var keybindCount = 0
        var pausedIgnored = 0

        for mod in mods where mod.isActive {
            for leaf in ConfigEditorModel.leaves(of: mod.tree) {
                switch classify(leaf: leaf) {
                case .keybind(let combos):
                    keybindCount += 1
                    for combo in combos where !combo.isEmpty {
                        index[combo, default: []].append(
                            .init(modID: mod.id, modName: mod.name, keyPath: leaf.keyPath))
                        // Conflit jeu : combinaison à bouton unique uniquement.
                        if combo.buttons.count == 1, let button = combo.buttons.first {
                            for control in GameControlDefaults.controls
                            where control.buttons.contains(button) {
                                gameIndex[control.name, default: []].append(
                                    .init(modID: mod.id, modName: mod.name, keyPath: leaf.keyPath))
                            }
                        }
                    }
                case .unrecognized(let raw):
                    unrecognized.append(.init(modID: mod.id, modName: mod.name,
                                              keyPath: leaf.keyPath, raw: raw))
                case .notKeybind:
                    break
                }
            }
        }
        pausedIgnored = mods.filter { !$0.isActive }.count

        let collisions = index
            .filter { Set($0.value.map(\.modID)).count >= 2 }
            .map { KeybindCollision(combo: $0.key, uses: $0.value.sorted { $0.modName < $1.modName }) }
            .sorted { $0.combo < $1.combo }
        let gameConflicts = gameIndex
            .map { name, uses in
                GameControlConflict(
                    control: GameControlDefaults.controls.first { $0.name == name }!,
                    uses: uses.sorted { $0.modName < $1.modName })
            }
            .sorted { $0.control.name < $1.control.name }
        unrecognized.sort { ($0.modName, $0.keyPath.joined()) < ($1.modName, $1.keyPath.joined()) }

        return KeybindReport(collisions: collisions, gameConflicts: gameConflicts,
                             unrecognized: unrecognized,
                             scannedMods: mods.filter(\.isActive).count,
                             keybindCount: keybindCount, pausedIgnored: pausedIgnored)
    }
}
