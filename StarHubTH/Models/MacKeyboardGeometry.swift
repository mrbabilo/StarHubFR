import Foundation

/// La géométrie d'un clavier de MacBook, en unités de touche (1 = une
/// lettre), pour la vue clavier du rapport de raccourcis.
///
/// Deux formes : **ISO** (Europe — une touche de plus en haut à gauche,
/// `kVK_ISO_Section` 0x0A ; Entrée en L sur deux rangées ; Maj gauche
/// court) et **ANSI** (Entrée sur une rangée, Maj gauche large). JIS se
/// replie sur ANSI. Toutes les rangées font 14,5 unités ; la rangée de
/// fonctions est moins haute.
///
/// La géométrie ne porte **pas** de libellé ni de nom `SButton` pour les
/// touches à caractère : ils dépendent de la disposition active (lettres et
/// ponctuation se lisent par libellé — voir `MacKeyCodeMap`). L'appelant les
/// obtient par `UCKeyTranslate` puis `MacKeyCodeMap.capturedName`, la même
/// règle que la capture : la vue et l'éditeur ne peuvent pas diverger.
public enum MacKeyboardGeometry {

    public enum Kind: Sendable { case iso, ansi }

    public enum Shape: Equatable, Sendable {
        case normal
        /// Entrée ISO : deux rangées de haut, encoche en bas à gauche
        /// (`notch` = largeur de l'encoche, en unités).
        case isoEnter(notch: Double)
        /// Flèches haut et bas, demi-hauteur.
        case halfTop, halfBottom
    }

    public struct Key: Equatable, Sendable, Identifiable {
        /// `nil` : touche sans nom `SButton` (fn, Touch ID).
        public let keyCode: UInt16?
        public let row: Int
        public let x: Double
        public let width: Double
        /// Libellé fixe des touches nommées (« esc », « tab »…). `nil` : le
        /// libellé vient de la disposition active.
        public let label: String?
        public let glyph: String?
        public let shape: Shape

        public var id: String { keyCode.map { "k\($0)" } ?? "r\(row)x\(x)" }
    }

    public static let width = 14.5
    /// Hauteur de chaque rangée, en unités : 0 = fonctions.
    public static let rowHeights: [Double] = [0.75, 1, 1, 1, 1, 1]

    public static func keys(_ kind: Kind) -> [Key] {
        var keys = functionRow
        switch kind {
        case .iso: keys += isoMain
        case .ansi: keys += ansiMain
        }
        return keys + bottomRow
    }

    // MARK: - Rangées

    private static func key(_ code: UInt16?, _ row: Int, _ x: Double, _ w: Double = 1,
                            label: String? = nil, glyph: String? = nil,
                            shape: Shape = .normal) -> Key {
        Key(keyCode: code, row: row, x: x, width: w, label: label, glyph: glyph, shape: shape)
    }

    /// Une suite de touches à caractère d'une unité, à partir de `x`.
    private static func run(_ codes: [UInt16], row: Int, from x: Double) -> [Key] {
        codes.enumerated().map { key($0.element, row, x + Double($0.offset)) }
    }

    private static let functionRow: [Key] = {
        let fCodes: [UInt16] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
        var keys: [Key] = [key(0x35, 0, 0, 1.5, label: "esc")]
        for (offset, code) in fCodes.enumerated() {
            keys.append(key(code, 0, 1.5 + Double(offset), label: "F\(offset + 1)"))
        }
        keys.append(key(nil, 0, 13.5, label: "", glyph: "touchid"))
        return keys
    }()

    /// Rangée des chiffres, sans la touche de tête : 1…0, puis les deux
    /// touches de droite.
    private static let digitRun: [UInt16] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D, 0x1B, 0x18]
    private static let topLetters: [UInt16] = [0x0C, 0x0D, 0x0E, 0x0F, 0x11, 0x10, 0x20, 0x22, 0x1F, 0x23, 0x21, 0x1E]
    private static let homeLetters: [UInt16] = [0x00, 0x01, 0x02, 0x03, 0x05, 0x04, 0x26, 0x28, 0x25, 0x29, 0x27]
    private static let bottomLetters: [UInt16] = [0x06, 0x07, 0x08, 0x09, 0x0B, 0x2D, 0x2E, 0x2B, 0x2F, 0x2C]

    // Rangées construites instruction par instruction : une seule longue
    // concaténation `+` dépasse le temps de typage de Swift 6.0 (CI).
    private static let isoMain: [Key] = {
        var keys: [Key] = [key(0x0A, 1, 0)]
        keys += run(digitRun, row: 1, from: 1)
        keys.append(key(0x33, 1, 13, 1.5, label: "delete", glyph: "delete.left"))
        keys.append(key(0x30, 2, 0, 1.5, label: "tab", glyph: "arrow.right.to.line"))
        keys += run(topLetters, row: 2, from: 1.5)
        keys.append(key(0x24, 2, 13.5, 1, label: "return", glyph: "return", shape: .isoEnter(notch: 0.25)))
        keys.append(key(0x39, 3, 0, 1.75, label: "verr. maj", glyph: "capslock"))
        keys += run(homeLetters + [0x2A], row: 3, from: 1.75)
        keys.append(key(0x38, 4, 0, 1.25, label: "maj", glyph: "shift"))
        keys.append(key(0x32, 4, 1.25))
        keys += run(bottomLetters, row: 4, from: 2.25)
        keys.append(key(0x3C, 4, 12.25, 2.25, label: "maj", glyph: "shift"))
        return keys
    }()

    private static let ansiMain: [Key] = {
        var keys: [Key] = [key(0x32, 1, 0)]
        keys += run(digitRun, row: 1, from: 1)
        keys.append(key(0x33, 1, 13, 1.5, label: "delete", glyph: "delete.left"))
        keys.append(key(0x30, 2, 0, 1.5, label: "tab", glyph: "arrow.right.to.line"))
        keys += run(topLetters + [0x2A], row: 2, from: 1.5)
        keys.append(key(0x39, 3, 0, 1.75, label: "verr. maj", glyph: "capslock"))
        keys += run(homeLetters, row: 3, from: 1.75)
        keys.append(key(0x24, 3, 12.75, 1.75, label: "return", glyph: "return"))
        keys.append(key(0x38, 4, 0, 2.25, label: "maj", glyph: "shift"))
        keys += run(bottomLetters, row: 4, from: 2.25)
        keys.append(key(0x3C, 4, 12.25, 2.25, label: "maj", glyph: "shift"))
        return keys
    }()

    private static let bottomRow: [Key] = [
        key(nil, 5, 0, label: "fn", glyph: "globe"),
        key(0x3B, 5, 1, label: "control", glyph: "control"),
        key(0x3A, 5, 2, label: "option", glyph: "option"),
        key(0x37, 5, 3, 1.25, label: "command", glyph: "command"),
        key(0x31, 5, 4.25, 5, label: ""),
        key(0x36, 5, 9.25, 1.25, label: "command", glyph: "command"),
        key(0x3D, 5, 10.5, label: "option", glyph: "option"),
        key(0x7B, 5, 11.5, label: "", glyph: "arrowtriangle.left.fill"),
        key(0x7E, 5, 12.5, label: "", glyph: "arrowtriangle.up.fill", shape: .halfTop),
        key(0x7D, 5, 12.5, label: "", glyph: "arrowtriangle.down.fill", shape: .halfBottom),
        key(0x7C, 5, 13.5, label: "", glyph: "arrowtriangle.right.fill"),
    ]
}
