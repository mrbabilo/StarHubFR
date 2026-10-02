import Foundation

/// Le nom `SButton` d'une touche du clavier macOS (**C4-T10**, corrigé le
/// 2026-10-02). La capture de raccourci reçoit un `NSEvent` ; le mod attend
/// un nom que le `TryParse` de SMAPI lit.
///
/// **Le jeu lit le libellé de la touche, pas sa position.** Mesuré le
/// 2026-10-02 : MonoGame (seul moteur livré sur Mac, aucune FNA dans le
/// dossier du jeu) convertit `Keysym.Sym` — le code SDL **logique** — et ne
/// lit jamais `Scancode` ; la SDL du jeu (2.30.4), interrogée sur un AZERTY,
/// rend `q` pour la position US du A ; et en jeu, `Ctrl + Q` d'UI Info
/// Suite 2 répond à la touche **gravée** Q. La règle « position US »
/// d'avant venait de l'ère FNA (FNA#121) et n'est plus vraie.
///
/// D'où trois familles :
/// - **lettres et ponctuation** : nommées par le caractère que la
///   disposition courante donne à la touche (`capturedName`) ;
/// - **rangée des chiffres** : toujours `D1`…`D0` par position — la SDL
///   force ces codes quelle que soit la disposition (mesuré : sur AZERTY
///   la touche `&` rend `1`) ;
/// - **touches sans caractère** (F1–F20, flèches, édition, pavé
///   numérique) : la table par keyCode, indépendante de la disposition.
///
/// Les valeurs n'existent que dans la mesure où `SButtonTable` les porte,
/// ce qu'un test garantit.
public enum MacKeyCodeMap {

    /// keyCode → nom canonique. Deux keyCodes ne portent jamais le même
    /// nom : la table est la disposition physique, pas un alias.
    public static let table: [UInt16: String] = [
        // Lettres (kVK_ANSI_*)
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
        0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
        0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T", 0x20: "U",
        0x1F: "O", 0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x28: "K",
        0x2D: "N", 0x2E: "M",
        // Chiffres du rang supérieur
        0x12: "D1", 0x13: "D2", 0x14: "D3", 0x15: "D4", 0x17: "D5",
        0x16: "D6", 0x1A: "D7", 0x1C: "D8", 0x19: "D9", 0x1D: "D0",
        // Ponctuation du rang supérieur, noms XNA
        0x18: "OemPlus", 0x1B: "OemMinus", 0x32: "OemTilde",
        0x21: "OemOpenBrackets", 0x1E: "OemCloseBrackets", 0x2A: "OemBackslash",
        0x29: "OemSemicolon", 0x27: "OemQuotes", 0x2B: "OemComma",
        0x2F: "OemPeriod", 0x2C: "OemQuestion",
        // Édition et navigation
        0x24: "Enter", 0x30: "Tab", 0x31: "Space", 0x33: "Back",
        0x35: "Escape", 0x39: "CapsLock", 0x72: "Help",
        0x73: "Home", 0x74: "PageUp", 0x75: "Delete", 0x77: "End",
        0x79: "PageDown",
        0x7B: "Left", 0x7C: "Right", 0x7D: "Down", 0x7E: "Up",
        // Modificateurs physiques — la capture ne les pose pas seule (voir
        // `modifierNames`), ils sont ici pour la table complète.
        0x38: "LeftShift", 0x3C: "RightShift",
        0x3B: "LeftControl", 0x3E: "RightControl",
        0x3A: "LeftAlt", 0x3D: "RightAlt",
        0x37: "LeftWindows", 0x36: "RightWindows",
        // Fonctions
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5",
        0x61: "F6", 0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10",
        0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15",
        0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
        // Pavé numérique
        0x52: "NumPad0", 0x53: "NumPad1", 0x54: "NumPad2", 0x55: "NumPad3",
        0x56: "NumPad4", 0x57: "NumPad5", 0x58: "NumPad6", 0x59: "NumPad7",
        0x5B: "NumPad8", 0x5C: "NumPad9",
        0x41: "Decimal", 0x43: "Multiply", 0x45: "Add", 0x4B: "Divide",
        0x4E: "Subtract", 0x4C: "Separator",
        // Volume
        0x48: "VolumeUp", 0x49: "VolumeDown", 0x4A: "VolumeMute",
    ]

    /// Les modificateurs d'un événement capturé, en noms `SButton`. Un
    /// ⌘ devient `LeftWindows` : c'est la touche Windows/Méta de la table
    /// XNA que SMAPI lit — le nom historique, pas un jugement.
    public static let modifierNames: (shift: String, control: String,
                                      alt: String, command: String) =
        ("LeftShift", "LeftControl", "LeftAlt", "LeftWindows")

    /// Le nom d'un keyCode, `nil` hors table — la touche n'est pas
    /// capturable.
    public static func name(for keyCode: UInt16) -> String? {
        table[keyCode]
    }

    /// La ponctuation que le jeu reconnaît : caractère SDL → nom `SButton`.
    /// Copie de `KeyboardUtil._map` de `MonoGame.Framework.dll` livré avec
    /// le jeu (relevé dans l'IL le 2026-10-02), restreint aux caractères
    /// non alphanumériques. Un caractère absent (`)` `^` `$` `ù` `:` sur un
    /// AZERTY) **n'a pas d'équivalent** : le jeu ne voit pas cette touche.
    public static let punctuationByCharacter: [Character: String] = [
        "'": "OemQuotes", "+": "Add", ",": "OemComma", "-": "OemMinus",
        ".": "OemPeriod", "/": "OemQuestion", ";": "OemSemicolon",
        "<": "OemBackslash", "=": "OemPlus", "[": "OemOpenBrackets",
        "\\": "OemPipe", "]": "OemCloseBrackets", "`": "OemTilde",
    ]

    /// Une touche « à caractère » : son nom dépend de la disposition. Les
    /// chiffres `D1`…`D0` n'en sont pas — la SDL du jeu force la rangée des
    /// chiffres quelle que soit la gravure (sur AZERTY, `&` rend `1`) : la
    /// table par keyCode les nomme donc directement.
    static func isCharacterKey(_ name: String) -> Bool {
        (name.count == 1 && name.first?.isLetter == true) || name.hasPrefix("Oem")
    }

    /// Le nom que la capture écrit pour une touche pressée.
    ///
    /// - Parameters:
    ///   - keyCode: le keyCode macOS de l'événement.
    ///   - character: le caractère que la disposition **courante** donne à
    ///     cette touche, sans modificateur (`UCKeyTranslate`) ; `nil` sans
    ///     disposition lisible.
    /// - Returns: le nom `SButton`, ou `nil` quand le jeu ne peut pas lire
    ///   cette touche — la capture la refuse plutôt que d'écrire un nom
    ///   deviné.
    public static func capturedName(keyCode: UInt16, character: String?) -> String? {
        if let fixed = table[keyCode], !isCharacterKey(fixed) { return fixed }
        guard let text = character, text.count == 1, let ch = text.first else { return nil }
        if ch.isASCII, ch.isLetter { return text.uppercased() }
        return punctuationByCharacter[ch]
    }

    /// Le caractère à montrer à côté d'un nom enregistré, quand le nom seul
    /// ne le dit pas : `OemComma` → `,`. `nil` pour une lettre, un chiffre
    /// ou une touche nommée (`F8`, `Space`) — le nom suffit.
    public static func displayHint(storedName: String) -> String? {
        punctuationByCharacter.first { $0.value == storedName }.map { String($0.key) }
    }
}
