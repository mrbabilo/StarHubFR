import SwiftUI

/// Un lien qui se voit cliquable : main au survol, soulignement au survol,
/// atténué pendant l'appui, gris et sans main quand il est désactivé. Le
/// `.link` de SwiftUI n'a aucun état de survol sur macOS (retour du
/// 2026-10-01, onglet Performances).
struct HoverLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverLinkLabel(configuration: configuration)
    }

    private struct HoverLinkLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? AppDesign.Color.accent : Color.secondary)
                .underline(hovering && isEnabled)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(.rect)
                .onHover { hovering = $0 }
                .modifier(HandWhenEnabled(enabled: isEnabled))
        }
    }
}

extension ButtonStyle where Self == HoverLinkStyle {
    static var hoverLink: HoverLinkStyle { HoverLinkStyle() }
}

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
