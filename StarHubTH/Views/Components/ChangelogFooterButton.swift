import SwiftUI

/// Le journal des modifications de l'app, en bouton du pied de la barre
/// latérale — il y tenait une ligne entière, sur deux lignes en français,
/// pour une page qu'on ouvre après une mise à jour et rarement sinon.
///
/// La destination reste dans `SidebarOrder` (groupe `.footer`) : le menu
/// « Aller » et la palette ⌘K la trouvent toujours. Même habillage que
/// `ThemeToggle`, dont il partage la rangée.
struct ChangelogFooterButton: View {
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination

    var body: some View {
        let isActive = currentTab == .appChangelog
        let title = localization.L(L10n.Main.appChangelog)
        Button {
            currentTab = .appChangelog
        } label: {
            Image(systemName: "doc.text")
                .font(AppDesign.Font.caption)
                .foregroundColor(isActive ? .accentColor : .secondary)
                .opacity(isActive ? 1 : 0.6)
                .padding(.horizontal, AppDesign.Spacing.sm)
                .padding(.vertical, AppDesign.Spacing.xs)
                .background(isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
