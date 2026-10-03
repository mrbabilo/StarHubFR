import SwiftUI

/// La carte « Sonde » de l'onglet Performances : où en est la sonde
/// StarHubFR (absente, en pause, active et sa version), et pourquoi ne pas
/// installer Profiler — elle fait le même travail, sans seuil, et les deux
/// faussent mutuellement leurs mesures (D1 clos le 2026-10-03). La
/// détection vient de `ModPresence` (Core, testé).
struct PerformanceProbeSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    private var probe: ModPresence { ModPresence.resolve(uniqueId: ModPresence.probeId, in: viewModel.mods) }
    private var profiler: ModPresence { ModPresence.resolve(uniqueId: ModPresence.profilerId, in: viewModel.mods) }

    var body: some View {
        PerformanceCard {
            Text(localization.L(L10n.Performance.probeTitle))
                .font(AppDesign.Font.headline(.semibold))
            switch probe {
            case .absent:
                StateCard(icon: "gauge.with.dots.needle.bottom.0percent",
                          text: localization.L(L10n.Performance.probeAbsent),
                          actionTitle: nil) {}
            case .paused(let folderName, _):
                note(String(format: localization.L(L10n.Performance.probePaused), folderName))
                Button(localization.L(L10n.Performance.probeEnable)) {
                    if let mod = mod(named: folderName) { viewModel.toggleMod(mod) }
                }
                .buttonStyle(.bordered).pointingHandCursor()
            case .enabled(_, let version):
                Label(String(format: localization.L(L10n.Performance.probeEnabled), version),
                      systemImage: "checkmark.circle")
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(AppDesign.Color.success)
            }
            switch profiler {
            case .enabled(let folderName, _):
                Label(String(format: localization.L(L10n.Performance.profilerActive), folderName),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(AppDesign.Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
            case .paused(let folderName, _):
                note(String(format: localization.L(L10n.Performance.profilerInstalled), folderName))
            case .absent:
                EmptyView()
            }
            note(localization.L(L10n.Performance.probeNoProfiler))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Le mod à basculer, relu au clic : `mods` change sous nos pieds
    /// (scan, activation ailleurs) et `folderName` est la clé stable.
    private func mod(named folderName: String) -> ModItem? {
        viewModel.mods.flatMap(\.components).first { $0.folderName == folderName }
    }
}
