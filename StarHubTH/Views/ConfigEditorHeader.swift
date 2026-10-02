import SwiftUI

/// En-tête commun des pages (audit UX 2026-10-02) pour l'éditeur de config
/// d'un mod : le mod, le fichier édité, et le choix Visuel / Code — autrefois
/// dans la barre de la fenêtre, loin du contenu qu'il bascule.
struct ConfigEditorHeader: View {
    let mod: ModItem
    @ObservedObject var localization: LocalizationStore
    @Binding var selectedTab: Int

    var body: some View {
        PageHeader(icon: "slider.horizontal.3", title: mod.name,
                   subtitle: String(format: localization.L(L10n.Settings.configHeaderSubtitle), mod.folderName)) {
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
