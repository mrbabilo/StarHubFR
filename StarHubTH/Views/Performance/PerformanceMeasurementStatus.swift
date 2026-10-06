import SwiftUI

struct PerformanceMeasurementStatus: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore

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
                }
            }
            if store.plan != nil, viewModel.isGameRunning() {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(String(format: localization.L(L10n.PerformanceEvidence.guidedProgress), store.guidedMinuteCount))
                        .font(AppDesign.Font.footnote)
                        .task(id: context.date) {
                            if viewModel.navigationStore.diagnosticsSegment == .performance {
                                await store.reload(gameDir: viewModel.gameDir)
                            }
                        }
                }
            }
            if store.status == .loading { ProgressView(localization.L(L10n.Performance.loading)).controlSize(.small) }
            if viewModel.isBenchmarkActive {
                Text(localization.L(L10n.PerformanceEvidence.benchmarkBusy)).font(AppDesign.Font.footnote)
            }
        }
    }
}
