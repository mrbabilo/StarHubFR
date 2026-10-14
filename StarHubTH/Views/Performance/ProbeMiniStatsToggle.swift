import SwiftUI

/// Les mini-stats en jeu (FPS, P50/P99, mémoire) depuis l'onglet Performances :
/// l'option existait dans le menu de config en jeu seulement, coupée par
/// défaut — introuvable pendant une mesure. La sonde lit sa config au
/// lancement : un changement vaut pour la partie suivante.
struct ProbeMiniStatsToggle: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let presence: ModPresence
    @State private var loaded: ProbeOptionsFile.Loaded = .unavailable
    @State private var isOn = ProbeOptions.defaultMiniStats

    private var url: URL? { ProbeOptionsFile.url(gameDir: viewModel.gameDir, presence: presence) }

    var body: some View {
        Group {
            if case .options(let options) = loaded {
                Toggle(isOn: $isOn) {
                    Text(localization.L(L10n.Mods.probeOptionsMiniStats)).font(AppDesign.Font.footnote)
                }
                .toggleStyle(.switch).controlSize(.mini)
                .help(localization.L(L10n.Mods.probeOptionsMiniStatsHelp) + "\n"
                      + localization.L(L10n.Mods.probeOptionsLaunchNote))
                .onChange(of: isOn) { _, value in
                    guard value != options.showMiniStats, let url else { return }
                    let next = ProbeOptions(measureHarmonyPatches: options.measureHarmonyPatches,
                                            measureTextures: options.measureTextures, showMiniStats: value)
                    do {
                        try ProbeOptionsFile.write(next, to: url)
                        loaded = .options(next)
                    } catch {
                        viewModel.log("Options de la sonde non écrites : \(error)", level: .warning)
                        isOn = options.showMiniStats
                    }
                }
            }
        }
        .onAppear {
            loaded = ProbeOptionsFile.load(url)
            if case .options(let options) = loaded { isOn = options.showMiniStats }
        }
    }
}
