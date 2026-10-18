import SwiftUI
import Combine

/// La fermeture du jeu, telle que macOS l'annonce (SMAPI compris : il est
/// rattaché au bundle du jeu). Seule source : l'impact par mod et l'onglet
/// Performances se mettent à jour dessus.
enum GameExit {
    static var publisher: AnyPublisher<Void, Never> {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .filter { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                return GameProcess.isGame(localizedName: app?.localizedName)
            }
            .map { _ in () }
            // La sonde finit d'écrire ses fichiers dans les instants qui
            // suivent : relire tout de suite manquerait la dernière minute.
            .delay(for: .seconds(3), scheduler: RunLoop.main)
            .eraseToAnyPublisher()
    }
}

/// D5-C — statistiques et analyses à jour dès que le jeu est quitté, quel que
/// soit l'onglet affiché : l'historique d'impact intègre la session close.
struct GameExitRefresh: ViewModifier {
    var viewModel: StarHubTHViewModel

    func body(content: Content) -> some View {
        content.onReceive(GameExit.publisher) {
            // P5-7 — le journal de la session close, quelle que soit la page :
            // sans cela, Alertes et Santé gardaient celui d'avant jusqu'au
            // prochain rescan. La recherche du mod responsable et la mesure
            // pilotée le relisent déjà elles-mêmes : ne pas doubler.
            if viewModel.bisection.state == nil, !viewModel.pilot.isActive {
                viewModel.refreshSmapiLog()
            }
            // N-04 — les parties de la séance (jour, argent) : l'Accueil ne
            // rescanne plus à chaque arrivée, et le jeu écrit dans le dossier
            // de la partie, pas dans Saves.
            viewModel.reloadSaves()
            Task {
                await viewModel.modImpactStore.reload(mods: viewModel.mods, gameRunning: viewModel.isGameRunning(),
                                                      gameDir: viewModel.gameDir)
            }
        }
    }
}

extension View {
    func refreshesStatsWhenGameQuits(_ viewModel: StarHubTHViewModel) -> some View {
        modifier(GameExitRefresh(viewModel: viewModel))
    }
}
