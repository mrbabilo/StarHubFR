import SwiftUI
import Charts

/// D5-B — une tuile de la carte « Chargements » : la dernière durée, le
/// verdict avant/après (glyphe + teinte + texte, patron de
/// `PerformanceHeader`), les mesures de chaque côté en points, puis les
/// écarts par mod. Le graphique montre, la ligne de durées sous lui prouve.
struct PerformanceLoadsVerdict: View {
    @ObservedObject var localization: LocalizationStore
    let titleKey: String
    let breakdown: ProbeLoadBreakdown
    let comparison: ProbeLoadComparisonResult?
    let isCold: Bool
    let displayName: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            Text(localization.L(titleKey)).font(AppDesign.Font.footnote).foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.xs) {
                Text(PerformanceLoadsSection.duration(breakdown.record.totalMs))
                    .font(AppDesign.Font.rowTitle(.semibold)).monospacedDigit()
                if breakdown.record.reload { badge(L10n.Performance.loadsReload) }
                if isCold { badge(L10n.Performance.loadsColdDisk) }
                if !breakdown.record.complete { badge(L10n.Performance.loadsIncomplete) }
            }
            if let comparison {
                verdict(comparison)
                if let date = comparison.before.compactMap(\.at).max() {
                    Text(String(format: localization.L(L10n.Performance.loadsComparedTo),
                                date.formatted(date: .abbreviated, time: .shortened)))
                        .font(AppDesign.Font.caption).foregroundColor(.secondary)
                }
                sides(comparison)
                deltas(comparison)
            }
        }
        .padding(AppDesign.Spacing.sm)
        .frame(width: 290, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppDesign.Radius.section)
            .fill(Color.primary.opacity(AppDesign.Opacity.subtle)))
        // Liseré de la couleur du sens, seulement pour un verdict tranché.
        .overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.section)
            .stroke(edge, lineWidth: 1.5))
    }

    private var edge: Color {
        guard let comparison, comparison.verdict.isDecided else { return .clear }
        return style(comparison.verdict).color.opacity(0.6)
    }

    private func badge(_ key: String) -> some View {
        Text(localization.L(key)).font(AppDesign.Font.caption)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(AppDesign.Opacity.light)))
    }

    private func style(_ verdict: ProbeLoadVerdict) -> (icon: String, color: Color) {
        switch verdict {
        case .faster: return ("hare", AppDesign.Color.success)
        case .slower: return ("tortoise", AppDesign.Color.warning)
        case .noDifference: return ("equal", .secondary)
        case .grayZone: return ("questionmark", .secondary)
        }
    }

    private func verdict(_ c: ProbeLoadComparisonResult) -> some View {
        Label(verdictText(localization.L(titleKey), c), systemImage: style(c.verdict).icon)
            .font(AppDesign.Font.body(.semibold))
            .foregroundColor(style(c.verdict).color)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Une ligne par côté, un point par mesure : l'écart et la dispersion
    /// se voient (une zone grise s'explique d'un coup d'œil).
    private func sides(_ c: ProbeLoadComparisonResult) -> some View {
        let before = localization.L(L10n.Performance.before)
        let after = localization.L(L10n.Performance.after)
        let points = c.before.map { (before, $0) } + c.after.map { (after, $0) }
        return VStack(alignment: .leading, spacing: 2) {
            Chart(points, id: \.1.id) { side, record in
                PointMark(x: .value("s", record.totalMs / 1000), y: .value("", side))
                    .symbolSize(64)   // ≈ 8 pt
                    .foregroundStyle(by: .value("", side))
            }
            .chartForegroundStyleScale([before: AppDesign.Chart.before, after: AppDesign.Chart.after])
            .chartLegend(.hidden)   // l'axe des Y nomme chaque ligne
            .chartXScale(domain: .automatic(includesZero: false))
            .chartXAxisLabel("s", alignment: .trailing)
            .frame(height: 64)
            if !c.before.isEmpty { sideLine(before, .before, c.before) }
            if !c.after.isEmpty { sideLine(after, .after, c.after) }
        }
    }

    private func sideLine(_ name: String, _ side: ProbeChartSide, _ records: [ProbeLoadRecord]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.xs) {
            PerformanceSideDot(side: side)
            Text(String(format: localization.L(L10n.Performance.loadsSideLine), name,
                        records.map { PerformanceLoadsSection.duration($0.totalMs) }.joined(separator: ", ")))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .font(AppDesign.Font.caption).monospacedDigit().foregroundColor(.secondary)
    }

    private func deltas(_ c: ProbeLoadComparisonResult) -> some View {
        ForEach(c.modDeltas) { d in
            HStack(alignment: .firstTextBaseline) {
                Text(displayName(d.mod)).lineLimit(1).truncationMode(.middle)
                Spacer()
                // Indécis : l'écart reste gris, suffixé « indicatif ».
                PerformanceDelta(text: (d.deltaMs < 0 ? "−" : "+") + PerformanceLoadsSection.duration(abs(d.deltaMs)),
                                 delta: d.deltaMs,
                                 trend: c.verdict.isDecided ? (d.deltaMs < 0 ? .better : .worse) : .neutral)
                if !c.verdict.isDecided {
                    Text(localization.L(L10n.Performance.loadsIndicative)).foregroundColor(.secondary)
                }
            }
            .font(AppDesign.Font.footnote)
        }
    }

    private func verdictText(_ name: String, _ c: ProbeLoadComparisonResult) -> String {
        switch c.verdict {
        case .faster(let seconds, _):
            return String(format: localization.L(L10n.Performance.loadsFaster), name,
                          PerformanceLoadsSection.duration(seconds * 1000))
        case .slower(let seconds, _):
            return String(format: localization.L(L10n.Performance.loadsSlower), name,
                          PerformanceLoadsSection.duration(seconds * 1000))
        case .noDifference:
            return String(format: localization.L(L10n.Performance.loadsNoDifference), name)
        case .grayZone(let beforeCount, _):
            // Un seul point « avant » : seule une nouvelle session sous l'ancien état le complète.
            let key = beforeCount < 2 ? L10n.Performance.loadsGrayIndicative : L10n.Performance.loadsGrayRelaunch
            return String(format: localization.L(key), name)
        }
    }
}
