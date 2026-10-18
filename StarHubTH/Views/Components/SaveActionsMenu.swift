import SwiftUI

/// R6 (audit UX 2026-10-16, décision de l'auteur) — les actions d'une partie,
/// une seule liste dans un seul ordre, servie au menu « … » de la rangée et
/// au clic droit de la rangée comme de la carte. Avant, deux menus
/// différents : « Gestion des sauvegardes » d'un côté, « Modifier » de
/// l'autre, et Dupliquer / Ouvrir le dossier dans les deux ordres.
struct SaveActionItems: View {
    let save: SaveGameInfo
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// La confirmation de suppression vit chez l'hôte (un seul présentateur).
    let onDelete: () -> Void

    var body: some View {
        let navigation = viewModel.navigationStore
        Button { navigation.openSave(save, segment: .details) } label: {
            Label(localization.L(L10n.Saves.edit), systemImage: "pencil")
        }
        Button { navigation.openSave(save, segment: .mods) } label: {
            Label(localization.L(L10n.Saves.segmentModsAction), systemImage: "shippingbox")
        }
        Button { navigation.openSave(save, segment: .history) } label: {
            Label(localization.L(L10n.Saves.timeline), systemImage: "clock.arrow.circlepath")
        }
        Divider()
        Button { viewModel.saveToDuplicate = save } label: {
            Label(localization.L(L10n.Saves.duplicate), systemImage: "doc.on.doc")
        }
        Button { viewModel.openSaveInFinder(info: save) } label: {
            Label(localization.L(L10n.Saves.openFolder), systemImage: "folder")
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label(localization.L(L10n.Saves.deleteSave), systemImage: "trash")
        }
        .disabled(viewModel.isSaveOperationRunning)
    }
}
