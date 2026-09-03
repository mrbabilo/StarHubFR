import Foundation

/// La table de référence des boutons, figée du relevé IL du 2026-08-28
/// (`ikdasm` sur StardewModdingAPI.dll — 190 entrées ; voir la spec §4).
/// Jamais recopiée de mémoire : générée par le spike, revérifiable par lui.
public enum SButtonTable {
    /// Valeur → nom canonique. Clavier, souris (≥ 1000), manettes.
    public static let canonicalByValue: [Int: String] = [
        0: "None",
        8: "Back",
        9: "Tab",
        13: "Enter",
        19: "Pause",
        20: "CapsLock",
        21: "Kana",
        25: "Kanji",
        27: "Escape",
        28: "ImeConvert",
        29: "ImeNoConvert",
        32: "Space",
        33: "PageUp",
        34: "PageDown",
        35: "End",
        36: "Home",
        37: "Left",
        38: "Up",
        39: "Right",
        40: "Down",
        41: "Select",
        42: "Print",
        43: "Execute",
        44: "PrintScreen",
        45: "Insert",
        46: "Delete",
        47: "Help",
        48: "D0",
        49: "D1",
        50: "D2",
        51: "D3",
        52: "D4",
        53: "D5",
        54: "D6",
        55: "D7",
        56: "D8",
        57: "D9",
        65: "A",
        66: "B",
        67: "C",
        68: "D",
        69: "E",
        70: "F",
        71: "G",
        72: "H",
        73: "I",
        74: "J",
        75: "K",
        76: "L",
        77: "M",
        78: "N",
        79: "O",
        80: "P",
        81: "Q",
        82: "R",
        83: "S",
        84: "T",
        85: "U",
        86: "V",
        87: "W",
        88: "X",
        89: "Y",
        90: "Z",
        91: "LeftWindows",
        92: "RightWindows",
        93: "Apps",
        95: "Sleep",
        96: "NumPad0",
        97: "NumPad1",
        98: "NumPad2",
        99: "NumPad3",
        100: "NumPad4",
        101: "NumPad5",
        102: "NumPad6",
        103: "NumPad7",
        104: "NumPad8",
        105: "NumPad9",
        106: "Multiply",
        107: "Add",
        108: "Separator",
        109: "Subtract",
        110: "Decimal",
        111: "Divide",
        112: "F1",
        113: "F2",
        114: "F3",
        115: "F4",
        116: "F5",
        117: "F6",
        118: "F7",
        119: "F8",
        120: "F9",
        121: "F10",
        122: "F11",
        123: "F12",
        124: "F13",
        125: "F14",
        126: "F15",
        127: "F16",
        128: "F17",
        129: "F18",
        130: "F19",
        131: "F20",
        132: "F21",
        133: "F22",
        134: "F23",
        135: "F24",
        144: "NumLock",
        145: "Scroll",
        160: "LeftShift",
        161: "RightShift",
        162: "LeftControl",
        163: "RightControl",
        164: "LeftAlt",
        165: "RightAlt",
        166: "BrowserBack",
        167: "BrowserForward",
        168: "BrowserRefresh",
        169: "BrowserStop",
        170: "BrowserSearch",
        171: "BrowserFavorites",
        172: "BrowserHome",
        173: "VolumeMute",
        174: "VolumeDown",
        175: "VolumeUp",
        176: "MediaNextTrack",
        177: "MediaPreviousTrack",
        178: "MediaStop",
        179: "MediaPlayPause",
        180: "LaunchMail",
        181: "SelectMedia",
        182: "LaunchApplication1",
        183: "LaunchApplication2",
        186: "OemSemicolon",
        187: "OemPlus",
        188: "OemComma",
        189: "OemMinus",
        190: "OemPeriod",
        191: "OemQuestion",
        192: "OemTilde",
        202: "ChatPadGreen",
        203: "ChatPadOrange",
        219: "OemOpenBrackets",
        220: "OemPipe",
        221: "OemCloseBrackets",
        222: "OemQuotes",
        223: "Oem8",
        226: "OemBackslash",
        229: "ProcessKey",
        242: "OemCopy",
        243: "OemAuto",
        244: "OemEnlW",
        246: "Attn",
        247: "Crsel",
        248: "Exsel",
        249: "EraseEof",
        250: "Play",
        251: "Zoom",
        253: "Pa1",
        254: "OemClear",
        1000: "MouseLeft",
        1001: "MouseRight",
        1002: "MouseMiddle",
        1003: "MouseX1",
        1004: "MouseX2",
        2001: "DPadUp",
        2002: "DPadDown",
        2004: "DPadLeft",
        2008: "DPadRight",
        2016: "ControllerStart",
        2032: "ControllerBack",
        2064: "LeftStick",
        2128: "RightStick",
        2256: "LeftShoulder",
        2512: "RightShoulder",
        4048: "BigButton",
        6096: "ControllerA",
        10192: "ControllerB",
        18384: "ControllerX",
        34768: "ControllerY",
        2099152: "LeftThumbstickLeft",
        4196304: "RightTrigger",
        8390608: "LeftTrigger",
        16779216: "RightThumbstickUp",
        33556432: "RightThumbstickDown",
        67110864: "RightThumbstickRight",
        134219728: "RightThumbstickLeft",
        268437456: "LeftThumbstickUp",
        536872912: "LeftThumbstickDown",
        1073743824: "LeftThumbstickRight",
    ]
    /// Noms canoniques en minuscules → canonique (recherche leniente).
    public static let canonicalByLowerName: [String: String] =
        Dictionary(uniqueKeysWithValues: canonicalByValue.values.map { ($0.lowercased(), $0) })
    /// L'intersection clavier XNA Keys ∩ SButton (tâche 0, step 2) :
    /// les seuls entiers qu'un `config.json` peut légitimement porter.
    public static let keyboardValues: Set<Int> = [0, 8, 9, 13, 19, 20, 21, 25, 27, 28, 29, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 144, 145, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 186, 187, 188, 189, 190, 191, 192, 202, 203, 219, 220, 221, 222, 223, 226, 229, 242, 243, 244, 246, 247, 248, 249, 250, 251, 253, 254]

    public static func canonicalName(for input: String) -> String? {
        canonicalByLowerName[input.lowercased()]
    }
}

/// Une combinaison : ensemble de boutons, trié, canonique. L'ordre
/// d'écriture n'a pas de sens au déclenchement — `GetState` de SMAPI
/// exige tous les boutons enfoncés — donc la forme canonique est l'ensemble.
public struct KeybindCombo: Equatable, Hashable, Sendable, Comparable {
    public let buttons: [String]

    public init?(buttons: [String]) {
        let unique = Array(Set(buttons)).sorted()
        // Un nom inconnu ne doit jamais entrer : le parseur valide avant.
        guard unique.allSatisfy({ SButtonTable.canonicalName(for: $0) == $0 }) else { return nil }
        self.buttons = unique
    }

    public var isEmpty: Bool { buttons.isEmpty }
    /// R2 : une combinaison vide ou un nom seul d'un caractère ne
    /// distinguent pas un raccourci d'un texte banal.
    public var isDistinctive: Bool {
        if buttons.isEmpty { return false }
        if buttons.count > 1 { return true }
        return buttons[0].count > 1
    }
    public var display: String {
        buttons.isEmpty ? "None" : buttons.joined(separator: " + ")
    }
    public static func < (l: Self, r: Self) -> Bool { l.buttons.lexicographicallyPrecedes(r.buttons) }
}

public enum KeybindParser {
    /// `nil` = la valeur n'est pas un raccourci lisible. Une combinaison
    /// vide (`None`) est valide et inerte.
    ///
    /// Le cas `.array` ne vient **jamais** du scanner : `ConfigEditorModel
    /// .leaves` aplatit les tableaux, chaque élément arrive comme sa propre
    /// feuille (`Keys.[0]`). Il reste ici parce qu'il est le contrat du type
    /// et qu'il est couvert par les tests — pas parce qu'un chemin de
    /// production l'emprunte.
    public static func parse(_ value: ConfigJSONTree.Value) -> [KeybindCombo]? {
        let tokens: [String]
        switch value {
        case .string(let s):
            // `\r\n` est un seul `Character` en Swift : remplacer « \r »
            // seul ne voit jamais le CR d'une fin de ligne Windows. Remplacer
            // la paire d'abord, puis les CR isolés (cf. ConfigJSONTree).
            let cleaned = s.replacingOccurrences(of: "\r\n", with: "\n")
                           .replacingOccurrences(of: "\r", with: "")
            // Une chaîne vide ou blanche n'est pas un raccourci lisible.
            guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            tokens = cleaned.split(separator: ",").map(String.init)
        case .array(let items):
            var toks: [String] = []
            for item in items {
                switch item {
                case .string(let s): toks.append(s)
                case .number(let lit):
                    guard let n = Int(lit) else { return nil }
                    toks.append(String(n))
                default: return nil
                }
            }
            tokens = toks
        case .number(let lit):
            guard let n = Int(lit) else { return nil }
            tokens = [String(n)]
        default:
            return nil
        }

        var combos: [KeybindCombo] = []
        for token in tokens {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.lowercased() == "none" {
                guard let c = KeybindCombo(buttons: []) else { return nil }
                combos.append(c); continue
            }
            var buttons: [String] = []
            var bareNone = false
            for part in trimmed.split(separator: "+") {
                let raw = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if let n = Int(raw) {
                    guard SButtonTable.keyboardValues.contains(n) else { return nil }
                    // L'entier 0 = None : combinaison vide, inerte (§3) —
                    // sinon deux mods hintés à 0 collisionnent sur « None ».
                    if n == 0 { bareNone = true; continue }
                    guard let name = SButtonTable.canonicalByValue[n] else { return nil }
                    buttons.append(name)
                } else if raw.lowercased() == "none" {
                    bareNone = true
                } else if let name = SButtonTable.canonicalName(for: raw) {
                    buttons.append(name)
                } else {
                    return nil
                }
            }
            // « None » nu → combinaison vide, inerte ; « None » au milieu
            // d'un combo (« None + F8 ») → jamais déclenchable, rejeté.
            if bareNone {
                guard buttons.isEmpty else { return nil }
                guard let c = KeybindCombo(buttons: []) else { return nil }
                combos.append(c)
                continue
            }
            guard let c = KeybindCombo(buttons: buttons) else { return nil }
            combos.append(c)
        }
        return combos
    }
}
