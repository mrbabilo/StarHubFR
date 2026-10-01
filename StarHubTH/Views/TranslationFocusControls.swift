import AppKit
import SwiftUI

/// Les deux gestes de l'espace de traduction, à droite des onglets de la
/// fiche : replier la chrome (bandeaux + barre latérale), passer en plein
/// écran. Échap sort du focus — posé sur un bouton qui n'existe qu'en focus,
/// pour que Échap ne l'entre jamais (audit UX 2026-10-02, 3ᵉ lot).
struct TranslationFocusControls: View {
    @Binding var focusMode: Bool
    @Binding var sidebarVisibility: NavigationSplitViewVisibility
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Button {
                withMotion(.snappy) {
                    focusMode.toggle()
                    sidebarVisibility = focusMode ? .detailOnly : .all
                }
            } label: {
                Label(localization.L(L10n.Mods.translationFocus),
                      systemImage: focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .help(localization.L(L10n.Mods.translationFocusHint))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointingHandCursor()
            if focusMode {
                // Échap : sortir du focus. Une feuille ouverte garde la
                // priorité du `.cancelAction` — elle se ferme d'abord. Le
                // bouton reste dans la hiérarchie (0 pt, invisible) : un
                // bouton absent ne reçoit pas de frappe.
                Button { exit() } label: { Text("").frame(width: 0, height: 0) }
                    .opacity(0)
                    .keyboardShortcut(.cancelAction)
            }
            Button {
                // Plein écran macOS : la fenêtre clé, pas l'app — le
                // sélecteur vit sur NSWindow aussi, et c'est la fenêtre
                // qu'on bascule.
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Label(localization.L(L10n.Mods.translationFullscreen),
                      systemImage: "arrow.up.left.and.arrow.down.right.circle")
                    .help(localization.L(L10n.Mods.translationFullscreenHint))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointingHandCursor()
        }
        .padding(.trailing, AppDesign.Spacing.lg)
    }

    private func exit() {
        withMotion(.snappy) {
            focusMode = false
            sidebarVisibility = .all
        }
    }
}
