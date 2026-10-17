import SwiftUI

/// C4b (décision de l'auteur, 2026-10-18) : un seul style de lien, le
/// `.link` natif ; l'ancien `HoverLinkStyle` (soulignement au survol) est
/// retiré. La main au survol reste, par `clickableCursor()`.

/// La main seulement si le geste est possible : un bouton désactivé garde la
/// flèche.
struct HandWhenEnabled: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled { content.pointingHandCursor() } else { content }
    }
}

extension View {
    /// Main au survol d'un bouton bordé ou sans bordure, sauf désactivé.
    func clickableCursor() -> some View { modifier(ClickableCursor()) }
}

private struct ClickableCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View { content.modifier(HandWhenEnabled(enabled: isEnabled)) }
}
