import SwiftUI

/// Le bouton « ? » de la barre d'outils (spec aide intégrée §4) : ouvre
/// l'aide à la section de la page affichée. Modificateur à part : `MainView`
/// est verrouillé par le cliquet de taille.
struct HelpLauncher: ViewModifier {
    var navigation: NavigationStore
    let currentTab: SidebarDestination
    @ObservedObject var localization: LocalizationStore
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigation.pendingHelpSection = HelpTopic.section(
                        for: currentTab,
                        diagnosticsSegment: navigation.diagnosticsSegment,
                        alertsSegment: navigation.alertsSegment)
                    openWindow(id: AppWindowID.help)
                } label: {
                    Label(localization.L(L10n.Help.pageButton), systemImage: "questionmark.circle")
                }
                .help(localization.L(L10n.Help.pageButton))
            }
        }
    }
}

extension View {
    func helpLauncher(navigation: NavigationStore, currentTab: SidebarDestination,
                      localization: LocalizationStore) -> some View {
        modifier(HelpLauncher(navigation: navigation, currentTab: currentTab, localization: localization))
    }
}
