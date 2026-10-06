import SwiftUI

/// Valeurs mesurées, inconnus explicites, noms entiers accessibles sans survol.
struct PerformanceCostsSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let report: ProbePerformanceReport
    @State private var showAll = false

    var body: some View {
        let rows = showAll ? report.costRows : Array(report.costRows.prefix(8))
        let maximum = max(1, report.costRows.flatMap { [$0.before, $0.after].compactMap { $0 } }.max() ?? 1)
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(localization.L(L10n.Performance.sectionCosts)).font(AppDesign.Font.headline(.semibold))
            Text(localization.L(L10n.PerformanceEvidence.costUnitHelp)).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            if rows.isEmpty { Text(localization.L(L10n.PerformanceEvidence.unavailable)).foregroundStyle(.secondary) }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Button { open(row.modId) } label: {
                        Text(PerformanceFormatting.modName(row.modId, viewModel: viewModel))
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }.buttonStyle(.hoverLink).help(row.modId)
                    bar(row.before, side: .before, maximum: maximum)
                    bar(row.after, side: .after, maximum: maximum)
                    if let delta = row.delta {
                        PerformanceDelta(text: "Δ \(PerformanceFormatting.number(delta, fraction: 2)) ms/s", delta: delta, trend: ProbeTrend.ofCost(delta))
                    }
                }
            }
            if report.costRows.count > 8 {
                Button(showAll ? localization.L(L10n.Performance.impactShowLess)
                       : String(format: localization.L(L10n.Performance.impactShowAll), report.costRows.count)) { showAll.toggle() }
                    .buttonStyle(.hoverLink)
            }
        }
    }

    private func bar(_ value: Double?, side: ProbeChartSide, maximum: Double) -> some View {
        let name = localization.L(side == .before ? L10n.Performance.before : L10n.Performance.after)
        return VStack(alignment: .leading, spacing: 2) {
            SplitRow { Text(name) } trailing: {
                if let value { Text("\(PerformanceFormatting.number(value, fraction: 2)) ms/s").monospacedDigit() }
                else { Text(localization.L(L10n.PerformanceEvidence.missingMetric)) }
            }.font(AppDesign.Font.footnote)
            if let value {
                ProgressView(value: value, total: maximum)
                    .tint(side == .before ? AppDesign.Chart.before : AppDesign.Chart.after)
                    .accessibilityLabel(name).accessibilityValue("\(PerformanceFormatting.number(value, fraction: 2)) ms/s")
            }
        }
    }

    private func open(_ modId: String) {
        guard let mod = ProbePerformanceActions.target(modId: modId, in: viewModel.scanStore.mods) else { return }
        viewModel.navigationStore.openModDetail(folderName: mod.folderName)
    }
}
