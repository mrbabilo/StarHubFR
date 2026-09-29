import SwiftUI

/// Bandeau de tête (spec §3c.1) : trois tuiles et le verdict, puis la mesure
/// propre — démarrée jeu lancé seulement, vérifié au clic.
struct PerformanceHeader: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    @State private var needsGame = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            if let report = store.report {
                WrapHStack(spacing: AppDesign.Spacing.md) {
                    tile(L10n.Performance.tileFrame, report.comparison.frameP50, unit: "ms")
                    tile(L10n.Performance.tileP99, report.comparison.frameP99, unit: "ms")
                    tile(L10n.Performance.tileHeap, report.comparison.heap,
                         unit: localization.L(L10n.Performance.unitMB))
                }
                verdict(report.comparison.verdict)
            }
            measurement
        }
    }

    private func tile(_ key: String, _ measure: ProbeMeasureComparison, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localization.L(key)).font(AppDesign.Font.footnote).foregroundColor(.secondary)
            Text("\(number(measure.a.median)) → \(number(measure.b.median)) \(unit)")
                .font(AppDesign.Font.body(.semibold)).monospacedDigit()
            if case .netChange(_, let percent) = measure.verdict {
                Text(String(format: "%+.1f %%", percent))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary).monospacedDigit()
            }
        }
        .padding(AppDesign.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: AppDesign.Radius.md).fill(AppDesign.Color.controlBg))
    }

    private func verdict(_ verdict: ProbeMeasureComparison.Verdict) -> some View {
        let (icon, key, color): (String, String, Color) = {
            switch verdict {
            case .netChange(let delta, _) where delta > 0:
                return ("tortoise", L10n.Performance.verdictSlower, AppDesign.Color.warning)
            case .netChange:
                return ("hare", L10n.Performance.verdictFaster, AppDesign.Color.success)
            case .noise:
                return ("equal", L10n.Performance.verdictNoise, .secondary)
            case .notEnoughData:
                return ("questionmark", L10n.Performance.verdictNotEnough, .secondary)
            }
        }()
        return Label(localization.L(key), systemImage: icon)
            .font(AppDesign.Font.body(.medium))
            .foregroundColor(color)
    }

    @ViewBuilder
    private var measurement: some View {
        if let open = store.openMeasurement {
            SplitRow {
                Text(String(format: localization.L(L10n.Performance.measureRunning), open.name,
                            open.start.formatted(date: .omitted, time: .shortened)))
                    .font(AppDesign.Font.footnote)
            } trailing: {
                Button(localization.L(L10n.Performance.measureStop)) {
                    store.stopMeasurement()
                    Task { await store.reload() }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Button(localization.L(L10n.Performance.measureStart)) {
                    // Jeu vérifié au clic, jamais au rendu.
                    let running = viewModel.isGameRunning()
                    needsGame = !running
                    let name = store.pendingMeasurementName
                        ?? String(format: localization.L(L10n.Performance.measureDefaultName),
                                  Date().formatted(date: .abbreviated, time: .shortened))
                    store.startMeasurement(name: name, gameRunning: running)
                }
                if let pending = store.pendingMeasurementName {
                    Text(pending).font(AppDesign.Font.footnote).foregroundColor(.secondary)
                }
                if needsGame {
                    Text(localization.L(L10n.Performance.measureNeedsGame))
                        .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                }
            }
        }
    }

    private func number(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—"
    }
}
