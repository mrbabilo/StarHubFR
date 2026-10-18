import SwiftUI

/// Un bouton icône du pied de la barre latérale, entre thème et langue :
/// les réglages, le journal des modifications (qui y tenait une ligne entière
/// de la liste, sur deux lignes en français) et l'aide des raccourcis clavier.
/// Trois pages qu'on ouvre rarement — une icône suffit, l'infobulle et VoiceOver
/// portent le titre. Même habillage que `ThemeToggle`, dont il partage la
/// rangée.
struct SidebarFooterIconButton: View {
    let icon: String
    let title: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(AppDesign.Font.caption)
                .foregroundColor(isActive ? .accentColor : .secondary)
                .opacity(isActive ? 1 : 0.6)
                .padding(.horizontal, AppDesign.Spacing.sm)
                .padding(.vertical, AppDesign.Spacing.xs)
                .background(isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).focusRing(cornerRadius: FocusRing.capsule)
        .pointingHandCursor()
        .iconHelp(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// Les pages et aides du pied : réglages, journal et raccourcis clavier.
struct SidebarFooterPages: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination

    var body: some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            SidebarFooterIconButton(icon: "gearshape.fill", title: localization.L(L10n.Settings.settings),
                                    isActive: currentTab == .settings) { currentTab = .settings }
            SidebarFooterIconButton(icon: "doc.text", title: localization.L(L10n.Main.appChangelog),
                                    isActive: currentTab == .appChangelog) { currentTab = .appChangelog }
            SidebarFooterIconButton(icon: "keyboard", title: localization.L(L10n.Shortcuts.title)) {
                vm.navigationStore.showsShortcutsHelp = true
            }
        }
    }
}
