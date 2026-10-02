import SwiftUI

/// La couleur d'un conflit de raccourci, **une seule règle pour tout
/// l'écran** (clavier, liste, tuiles) : collision entre mods actifs en
/// rouge, conflit avec un contrôle du jeu en orange. Toujours doublée du
/// glyphe — jamais la couleur seule.
enum KeybindConflictStyle {
    static let glyph = "exclamationmark.triangle.fill"

    static func color(_ kind: KeybindScanner.ConflictKind?) -> Color {
        switch kind {
        case .mods: AppDesign.Color.error
        case .game: AppDesign.Color.warning
        case nil: AppDesign.Color.accent
        }
    }
}
