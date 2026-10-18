import SwiftUI

/// Barre d'outils de l'éditeur : nom, dossier et choix Visuel / Code.
struct ConfigEditorHeader: View {
    let mod: ModItem
    @ObservedObject var localization: LocalizationStore
    @Binding var selectedTab: Int

    var body: some View {
        PageContextBar(icon: "slider.horizontal.3",
                       title: mod.name,
                       context: String(format: localization.L(L10n.Settings.configHeaderSubtitle), mod.folderName)) {
            Picker("", selection: $selectedTab) {
                Text(localization.L(L10n.Settings.configVisualEditor)).tag(0)
                Text(localization.L(L10n.Settings.configCodeEditor)).tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }
}
