import Foundation

/// Branchement de `UltraSmoothMeasureSetting` sur l'app : les textes, le
/// journal, la modale du seul cas qui demande au joueur de regarder. La règle et
/// l'écriture vivent en Core ; ici, rien que la parole.
@MainActor
enum UltraSmoothMeasureLive {
    /// Juste avant de lancer le jeu pour une mesure (guidée, pilotée, série de
    /// benchmark). Ne bloque jamais le lancement. Rend l'avertissement à
    /// montrer à côté du bouton, ou `nil`.
    @discardableResult
    static func beforeMeasure(_ viewModel: StarHubTHViewModel) -> String? {
        let loc = viewModel.localization
        let text: String
        switch UltraSmoothMeasureSetting.beforeMeasure(mods: viewModel.mods, gameDir: viewModel.gameDir,
                                                       backups: .shared) {
        case .notNeeded, .alreadyOff:
            return nil
        case .applied:
            viewModel.log(loc.L(L10n.Performance.usMeasureApplied), level: .info)
            return nil
        case .refused(.experimental): text = loc.L(L10n.Performance.usMeasureRefusedExperimental)
        case .refused(.oldSchema): text = loc.L(L10n.Performance.usMeasureRefusedSchema)
        case .refused(.unreadable): text = loc.L(L10n.Performance.usMeasureRefusedUnreadable)
        case .failed(let error): text = String(format: loc.L(L10n.Performance.usMeasureFailed), error)
        }
        viewModel.log(text, level: .warning)
        return text
    }

    /// À la sortie du jeu, et à l'apparition de la fenêtre (reprise après un
    /// plantage). `exitedAt` : le jeu est vu fermé depuis ce moment ; un
    /// lancement de mesure postérieur fait attendre la sortie suivante.
    static func afterGameExit(_ viewModel: StarHubTHViewModel, exitedAt: Date) {
        let loc = viewModel.localization
        switch UltraSmoothMeasureSetting.afterMeasure(gameRunning: viewModel.isGameRunning(), exitedAt: exitedAt) {
        case .nothingPending, .notYet, .alreadyOriginal:
            return
        case .restored:
            viewModel.log(loc.L(L10n.Performance.usMeasureRestored), level: .info)
        case .changedMeanwhile:
            // Choix de l'auteur (2026-11-11) : ne rien écraser, et le dire là
            // où on le voit — les deux options sont peut-être restées coupées.
            let text = loc.L(L10n.Performance.usMeasureChanged)
            viewModel.log(text, level: .warning)
            viewModel.showModal(message: text)
        case .failed(let error):
            viewModel.log(String(format: loc.L(L10n.Performance.usMeasureRestoreFailed), error), level: .warning)
        }
    }
}
