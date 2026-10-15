import SwiftUI

/// Le menu Aide (spec aide intégrée §4). Une vue et non des boutons nus :
/// elle lit `openWindow`, et ouvre l'aide même quand la fenêtre principale
/// est fermée — une intention posée pour `MainView` ne serait alors jamais
/// consommée.
struct HelpCommands: View {
    var navigation: NavigationStore
    @ObservedObject var localization: LocalizationStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(localization.L(L10n.Help.title)) {
            navigation.pendingHelpSection = nil
            openWindow(id: AppWindowID.help)
        }
        .keyboardShortcut("?", modifiers: .command)
        Button(localization.L(L10n.Shortcuts.title)) { navigation.showsShortcutsHelp = true }
            .keyboardShortcut(KeyEquivalent(Character(KeyboardShortcutCatalog.helpKey)), modifiers: .command)
    }
}
