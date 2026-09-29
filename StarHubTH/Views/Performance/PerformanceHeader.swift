import SwiftUI

/// Bandeau de tête (spec §3c.1) : trois tuiles et le verdict. La mesure
/// guidée vit dans `PerformanceGuidedBar` (D5-A).
struct PerformanceHeader: View {
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            if let report = store.report {
                WrapHStack(spacing: AppDesign.Spacing.md) {
                    // Trois temps ou tailles : moins, c'est mieux.
                    tile(L10n.Performance.tileFrame, report.comparison.frameP50, unit: "ms",
                         help: L10n.Performance.tileHelpFrame)
                    tile(L10n.Performance.tileP99, report.comparison.frameP99, unit: "ms",
                         help: L10n.Performance.tileHelpP99)
                    tile(L10n.Performance.tileHeap, report.comparison.heap,
                         unit: localization.L(L10n.Performance.unitMB), help: L10n.Performance.tileHelpHeap)
                }
                Text(localization.L(L10n.Performance.tileLegend))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                verdict(report.comparison.verdict)
            }
        }
    }

    private func tile(_ key: String, _ measure: ProbeMeasureComparison, unit: String, help: String) -> some View {
        let trend = ProbeTrend.of(measure.verdict, lowerIsBetter: true)
        return VStack(alignment: .leading, spacing: 2) {
            Text(localization.L(key)).font(AppDesign.Font.footnote).foregroundColor(.secondary)
                .help(localization.L(help))
            Text("\(number(measure.a.median)) → \(number(measure.b.median)) \(unit)")
                .font(AppDesign.Font.body(.semibold)).monospacedDigit()
            if case .netChange(let delta, let percent) = measure.verdict {
                PerformanceDelta(text: String(format: "%+.1f %%", percent), delta: delta, trend: trend)
            }
        }
        .padding(AppDesign.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: AppDesign.Radius.md).fill(AppDesign.Color.controlBg))
        // Liseré de la couleur du sens, seulement pour un écart net.
        .overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.md)
            .stroke(trend == .neutral ? .clear : trend.tint.opacity(0.6), lineWidth: 1.5))
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
            .font(AppDesign.Font.body(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, AppDesign.Spacing.sm).padding(.vertical, AppDesign.Spacing.xs)
            .background(color.opacity(AppDesign.Opacity.light),
                        in: RoundedRectangle(cornerRadius: AppDesign.Radius.sm))
    }

    private func number(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—"
    }
}
