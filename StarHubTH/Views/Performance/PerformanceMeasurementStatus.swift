import SwiftUI

struct PerformanceMeasurementStatus: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    /// Fin de série pilotée : la Synthèse passe sur « Comparer » (`scroll` : y mener).
    var revealComparison: (_ scroll: Bool) -> Void

    private var bundledProbeVersion: String? {
        ProbeBundle.bundledFolder(resourcesURL: Bundle.main.resourceURL).flatMap(ProbeBundle.version(ofFolder:))
    }

    var body: some View {
        let probe = ModPresence.resolve(uniqueId: ModPresence.probeId, in: viewModel.mods)
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            switch probe {
            case .absent, .paused:
                PerformanceProbeSection(viewModel: viewModel, localization: localization, store: store)
            case .enabled(_, let version):
                Label(String(format: localization.L(L10n.Performance.probeEnabled), version), systemImage: "waveform.path")
                    .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                if case .outdated = GuidedProtocol.readiness(probeVersion: version, isEnabled: true) {
                    PerformanceProbeSection(viewModel: viewModel, localization: localization, store: store)
                } else if !GuidedProtocol.supportsPilot(version) {
                    // Guidage possible, pilotage non : sans ce mot, le bouton
                    // « Mesure pilotée » resterait caché sans explication.
                    Text(String(format: localization.L(L10n.PerformancePilot.needsProbeUpdate),
                                GuidedProtocol.pilotMinimumVersion.map(String.init).joined(separator: ".")))
                        .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PerformanceProbeSection(viewModel: viewModel, localization: localization, store: store)
                } else if case .update = ProbeBundle.action(bundled: bundledProbeVersion, presence: probe) {
                    // L'app embarque une sonde plus récente : sans cette carte,
                    // la mise à jour ne se proposait que dans le volet replié
                    // « Réglages » (0.9.26 jamais déployée, 2026-10-13).
                    PerformanceProbeSection(viewModel: viewModel, localization: localization, store: store)
                }
            }
            // Pilotage : le plan est écrit par le runner, pas par ce store —
            // la relecture démarre sans attendre que `store.plan` le voie.
            let piloting = viewModel.pilot.isActive
            if store.plan != nil || piloting, viewModel.isGameRunning() {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Group {
                        // En pilotage, la ligne d'état du pilote porte le compte.
                        if piloting {
                            Color.clear.frame(width: 0, height: 0)
                        } else {
                            Text(String(format: localization.L(L10n.PerformanceEvidence.guidedProgress),
                                        store.guidedMinuteCount))
                                .font(AppDesign.Font.footnote)
                        }
                    }
                    .task(id: context.date) {
                        if viewModel.navigationStore.diagnosticsSegment == .performance {
                            await PerformanceReloadLog.run(viewModel, cause: "minuterie de mesure, 15 s") {
                                await store.reload(gameDir: viewModel.gameDir)
                            }
                        }
                    }
                }
            }
            PerformancePilotStatus(viewModel: viewModel, localization: localization, store: store,
                                   revealComparison: revealComparison)
            if store.status == .loading { ProgressView(localization.L(L10n.Performance.loading)).controlSize(.small) }
            if viewModel.isBenchmarkActive {
                Text(localization.L(L10n.PerformanceEvidence.benchmarkBusy)).font(AppDesign.Font.footnote)
            }
        }
    }
}
