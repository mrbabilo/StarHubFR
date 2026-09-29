import SwiftUI
import Charts

/// « Coût par mod » (spec §3c.4) : les 8 plus fortes variations, avant et
/// après reliés ; le reste replié. Nom du mod en encre, jamais la couleur de
/// la série ; clic dans le tableau : la fiche du mod.
struct PerformanceCostsSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let report: ProbePerformanceReport
    @State private var hovered: ProbeDumbbell?

    var body: some View {
        let data = ProbeComparisonChart.dumbbells(report.costDeltas)
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.Performance.sectionCosts)).font(AppDesign.Font.headline(.semibold))
            if !data.rows.isEmpty {
                chart(data.rows)
                Text(hovered.map { "\(name($0.modId)) · \(values($0))" } ?? " ")
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
            ForEach(data.rows) { row in tableRow(row) }
            if data.others > 0 {
                Text(String(format: localization.L(L10n.Performance.costOthers), data.others))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
        }
    }

    private func chart(_ rows: [ProbeDumbbell]) -> some View {
        let before = localization.L(L10n.Performance.before)
        let after = localization.L(L10n.Performance.after)
        return Chart {
            ForEach(rows) { row in
                if let a = row.before, let b = row.after {
                    RuleMark(xStart: .value("ms/s", a), xEnd: .value("ms/s", b),
                             y: .value("Mod", row.modId))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(.secondary)
                }
                if let a = row.before {
                    PointMark(x: .value("ms/s", a), y: .value("Mod", row.modId))
                        .symbolSize(64).foregroundStyle(by: .value("Côté", before))
                }
                if let b = row.after {
                    PointMark(x: .value("ms/s", b), y: .value("Mod", row.modId))
                        .symbolSize(64).foregroundStyle(by: .value("Côté", after))
                }
            }
        }
        .chartForegroundStyleScale([before: AppDesign.Chart.before, after: AppDesign.Chart.after])
        .chartLegend(position: .top, alignment: .leading)
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    // L'axe porte l'identifiant (unique) ; on affiche le nom.
                    Text(value.as(String.self).map(name) ?? "")
                        .lineLimit(1).truncationMode(.middle).foregroundColor(.secondary)
                }
            }
        }
        .chartOverlay { proxy in
            ChartHover(proxy: proxy) { local in
                let modId: String? = proxy.value(atY: local.y)
                hovered = rows.first { $0.modId == modId }
            } onEnd: {
                hovered = nil
            } onTap: {}
        }
        .frame(height: CGFloat(rows.count) * 26 + 40)
    }

    private func tableRow(_ row: ProbeDumbbell) -> some View {
        SplitRow {
            Button { open(row.modId) } label: {
                Text(name(row.modId)).lineLimit(1).truncationMode(.middle)
            }
            .buttonStyle(.link)
            .help(row.modId)
        } trailing: {
            Text(values(row)).font(AppDesign.Font.footnote).foregroundColor(.secondary).monospacedDigit()
        }
    }

    private func values(_ row: ProbeDumbbell) -> String {
        switch (row.before, row.after) {
        case (nil, let after?): return "\(localization.L(L10n.Performance.costNew)) · \(number(after)) ms/s"
        case (let before?, nil): return "\(localization.L(L10n.Performance.costRemoved)) · \(number(before)) ms/s"
        default:
            return String(format: localization.L(L10n.Performance.costRow), number(row.before), number(row.after))
        }
    }

    private func open(_ modId: String) {
        guard let mod = ProbePerformanceActions.target(modId: modId, in: viewModel.scanStore.mods) else { return }
        viewModel.navigationStore.openModDetail(folderName: mod.folderName)
    }

    private func name(_ modId: String) -> String {
        viewModel.scanStore.mods.flattenedMods
            .first { $0.uniqueId.caseInsensitiveCompare(modId) == .orderedSame }?.name ?? modId
    }

    private func number(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—"
    }
}
