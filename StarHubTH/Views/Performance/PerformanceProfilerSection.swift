import SwiftUI

/// D1-T1 — la carte Profiler de l'onglet Performances : où en est le mod
/// (absent, en pause, actif) et le geste qui suit. La détection vient de
/// `ProfilerDetection` (Core, testé) ; ici, l'affichage et les deux actions —
/// ouvrir la page du mod, activer le dossier trouvé.
struct PerformanceProfilerSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    private var detection: ProfilerDetection {
        ProfilerDetection.resolve(mods: viewModel.mods)
    }

    var body: some View {
        PerformanceCard {
            Text(localization.L(L10n.Performance.profilerTitle))
                .font(AppDesign.Font.headline(.semibold))
            switch detection {
            case .absent:
                StateCard(icon: "gauge.with.dots.needle.bottom.0percent",
                          text: localization.L(L10n.Performance.profilerAbsent),
                          actionTitle: localization.L(L10n.Performance.profilerPage)) {
                    NSWorkspace.shared.open(URL(string:
                        "https://github.com/SinZ163/StardewMods/tree/main/Profiler")!)
                }
                Text(localization.L(L10n.Performance.profilerAbsentHint))
                    .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .paused(let folderName):
                Text(String(format: localization.L(L10n.Performance.profilerPaused), folderName))
                    .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(localization.L(L10n.Performance.profilerEnable)) {
                    if let mod = mod(named: folderName) { viewModel.toggleMod(mod) }
                }
                .buttonStyle(.bordered).pointingHandCursor()
            case .enabled:
                Text(localization.L(L10n.Performance.profilerEnabledHint))
                    .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(localization.L(L10n.Performance.profilerEnabledOk), systemImage: "checkmark.circle")
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(AppDesign.Color.success)
            }
        }
    }

    /// Le mod à basculer, relu au clic : `mods` change sous nos pieds
    /// (scan, activation ailleurs) et `folderName` est la clé stable.
    private func mod(named folderName: String) -> ModItem? {
        viewModel.mods.flatMap(\.components).first { $0.folderName == folderName }
    }
}
