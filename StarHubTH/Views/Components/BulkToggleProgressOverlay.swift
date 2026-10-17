import SwiftUI

/// La progression d'une bascule groupée, sur toute la zone de contenu, et la
/// lecture des sauvegardes qui la précède quand des mods passent en pause
/// (A1-T8, `SaveFingerprintPauseStore`). Elle
/// vivait dans la liste des mods seule : une bascule lancée d'ailleurs —
/// « Réactiver ces mods » d'une partie (P5-8), « Revenir à un état
/// d'avant », un groupe — déplaçait des dizaines de dossiers sans rien
/// montrer (constat de l'auteur, 2026-10-17).
struct BulkToggleProgressOverlay: ViewModifier {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    func body(content: Content) -> some View {
        content.overlay {
            if let progress = viewModel.bulkToggleProgress, progress.total > 0 {
                ModalProgressOverlay(
                    label: viewModel.bulkToggleEnabling
                        ? localization.L(L10n.Mods.enablingAllProgress)
                        : localization.L(L10n.Mods.disablingAllProgress),
                    done: progress.done,
                    total: progress.total)
            } else if let reading = viewModel.saveFingerprintPauseStore.checkProgress {
                ModalProgressOverlay(label: localization.L(L10n.Saves.fingerprintReading),
                                     done: reading.done, total: reading.total)
            }
        }
    }
}

extension View {
    func bulkToggleProgress(viewModel: StarHubTHViewModel, localization: LocalizationStore) -> some View {
        modifier(BulkToggleProgressOverlay(viewModel: viewModel, localization: localization))
    }
}
