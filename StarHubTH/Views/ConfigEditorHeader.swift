import SwiftUI

/// Barre de contexte de l'éditeur : dossier et choix Visuel / Code. Le nom du
/// mod reste porté par le titre de navigation.
struct ConfigEditorHeader: View {
    let mod: ModItem
    @ObservedObject var localization: LocalizationStore
    @Binding var selectedTab: Int

    var body: some View {
        PageContextBar(icon: "slider.horizontal.3",
                       context: String(format: localization.L(L10n.Settings.configHeaderSubtitle), mod.folderName)) {
            Picker("", selection: $selectedTab) {
                Text(localization.L(L10n.Settings.configVisualEditor)).tag(0)
                Text(localization.L(L10n.Settings.configCodeEditor)).tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, AppDesign.Spacing.xl)
        .padding(.vertical, AppDesign.Spacing.md)
    }
}
