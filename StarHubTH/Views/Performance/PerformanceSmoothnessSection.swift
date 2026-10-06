import SwiftUI
import Charts

/// Chronologie et détails utilisent exactement les lieux retenus par la métrique.
struct PerformanceSmoothnessSection: View {
    @ObservedObject var localization: LocalizationStore
    let report: ProbePerformanceReport
    @State private var measure: ProbeMetric = .frameP50
    @State private var selectedId: String?
    @State private var hoveredId: String?

    var body: some View {
        let chart = report.charts[measure]
        let data = (marks: chart?.marks ?? [], yMax: chart?.yMax)
        let activeMark = data.marks.first { $0.id == (hoveredId ?? selectedId) }
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(localization.L(L10n.Performance.sectionTimeline)).font(AppDesign.Font.headline(.semibold))
            Picker(localization.L(L10n.Performance.sectionSmoothness), selection: $measure) {
                ForEach(ProbeMetric.allCases, id: \.self) { Text(PerformanceMetricText.name($0, localization)).tag($0) }
            }.pickerStyle(.menu)
            if let result = report.metrics[measure] {
                Label(PerformanceMetricText.outcome(result.outcome, localization), systemImage: PerformanceMetricText.symbol(result.outcome))
                    .foregroundStyle(PerformanceMetricText.tint(result.outcome))
                coverage(result)
            }
            if let quality = report.quality[measure] {
                Text(PerformanceMetricText.quality(quality.level, localization)).font(AppDesign.Font.body(.semibold))
                ForEach(Array(quality.reasons.enumerated()), id: \.offset) { _, reason in
                    Text(PerformanceMetricText.reason(reason, localization)).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                }
            }
            timeline(.before, data: data)
            timeline(.after, data: data)
            // Hauteur toujours réservée : le survol remplit cette ligne sans
            // déplacer les explications et les détails situés dessous.
            Text(activeMark.map(markText) ?? " ")
                .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail).textSelection(.enabled)
            if measure == .work { note(L10n.PerformanceEvidence.workNote) }
            if measure == .frameP99 { note(L10n.PerformanceEvidence.p99Note) }
            if measure.isMemory { note(L10n.PerformanceEvidence.memoryNote) }
            DisclosureGroup(localization.L(L10n.PerformanceEvidence.details)) {
                distribution(chart)
                details(data.marks)
            }
        }
        .onChange(of: measure) { _, _ in selectedId = nil; hoveredId = nil }
        .onChange(of: report) { _, _ in selectedId = nil; hoveredId = nil }
    }

    private func coverage(_ result: ProbeMetricResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(sideName(.before)) · " + String(format: localization.L(L10n.PerformanceEvidence.coverage), result.keptBefore, result.excludedBefore))
            Text("\(sideName(.after)) · " + String(format: localization.L(L10n.PerformanceEvidence.coverage), result.keptAfter, result.excludedAfter))
        }.font(AppDesign.Font.footnote).foregroundStyle(.secondary)
    }

    private func timeline(_ side: ProbeChartSide, data: (marks: [ProbeTimelineMark], yMax: Double?)) -> some View {
        let marks = data.marks.filter { $0.side == side }
        let isFrame = measure == .frameP50 || measure == .frameP99
        let top = max(data.yMax ?? 1, isFrame ? 1000 / 60 : 1) * 1.05
        let lowX = min(0, data.marks.map(\.minutesFromStart).min() ?? 0)
        let highX = max(1, data.marks.map(\.minutesFromStart).max() ?? 1)
        let color = side == .before ? AppDesign.Chart.before : AppDesign.Chart.after
        return VStack(alignment: .leading, spacing: 4) {
            Label(sideName(side), systemImage: "circle.fill").font(AppDesign.Font.footnote).foregroundStyle(color)
            Chart {
                ForEach(marks) { mark in
                    if let value = mark.value {
                        LineMark(x: .value("min", mark.minutesFromStart), y: .value(unit, value), series: .value("segment", mark.segmentId))
                            .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("min", mark.minutesFromStart), y: .value(unit, value))
                            .foregroundStyle(color).symbolSize(mark.id == selectedId ? 65 : 25)
                            .accessibilityLabel(markText(mark))
                    } else {
                        RuleMark(x: .value("min", mark.minutesFromStart))
                            .foregroundStyle(.secondary.opacity(0.2)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                            .accessibilityLabel(markText(mark))
                    }
                }
                if isFrame {
                    RuleMark(y: .value("60 FPS", 1000.0 / 60))
                        .foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing) { Text("60 FPS").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            .chartXScale(domain: lowX...highX)
            .chartYScale(domain: 0...top)
            .chartXAxisLabel("min").chartYAxisLabel(unit)
            .frame(height: 125)
            .chartOverlay { proxy in
                ChartHover(proxy: proxy) { point in
                    guard let x: Double = proxy.value(atX: point.x) else { hoveredId = nil; return }
                    hoveredId = marks.min { abs($0.minutesFromStart - x) < abs($1.minutesFromStart - x) }?.id
                } onEnd: { hoveredId = nil } onTap: { selectedId = hoveredId }
            }
        }
    }

    @ViewBuilder
    private func distribution(_ data: ProbeChartData?) -> some View {
        if let data {
            ForEach(report.metrics[measure]?.locations ?? [], id: \.location) { location in
                Text(location.location).font(AppDesign.Font.body(.semibold))
                Chart {
                    ForEach(data.points.filter { $0.location == location.location }) { point in
                        PointMark(x: .value(unit, point.value), y: .value("side", point.side == .before ? 1 + point.jitter : point.jitter))
                            .foregroundStyle(point.side == .before ? AppDesign.Chart.before : AppDesign.Chart.after)
                            .accessibilityLabel("\(sideName(point.side)) · \(point.at) · \(PerformanceFormatting.number(point.value)) \(unit)")
                    }
                    ForEach(data.boxes.filter { $0.location == location.location }, id: \.side) { box in
                        RectangleMark(xStart: .value("Q1", box.q1), xEnd: .value("Q3", box.q3),
                                      yStart: .value("side", box.side == .before ? 0.65 : -0.35),
                                      yEnd: .value("side", box.side == .before ? 1.35 : 0.35))
                            .foregroundStyle(box.side == .before ? AppDesign.Chart.before : AppDesign.Chart.after).opacity(0.2)
                    }
                }
                .chartYScale(domain: -0.6...1.6)
                .chartYAxis { AxisMarks(values: [0, 1]) { value in AxisValueLabel(sideName(value.as(Int.self) == 1 ? .before : .after)) } }
                .chartXAxisLabel(unit).frame(height: 110)
            }
        }
    }

    private func details(_ marks: [ProbeTimelineMark]) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            note(L10n.PerformanceEvidence.heuristic)
            note(L10n.PerformanceEvidence.centralNote)
            if let result = report.metrics[measure] {
                ForEach(result.locations, id: \.location) { row in
                    Text(row.location).font(AppDesign.Font.body(.semibold))
                    statistic(.before, row.before)
                    statistic(.after, row.after)
                }
            }
            // Menu natif : clavier et VoiceOver accèdent aux mêmes détails que le clic.
            Picker(localization.L(L10n.PerformanceEvidence.point), selection: $selectedId) {
                Text("—").tag(Optional<String>.none)
                ForEach(marks) { mark in Text(markText(mark)).tag(Optional(mark.id)) }
            }.pickerStyle(.menu)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(marks) { mark in
                        Button { selectedId = mark.id } label: {
                            Text(markText(mark)).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).font(AppDesign.Font.footnote)
                    }
                }
            }.frame(maxHeight: 220)
        }
    }

    private func statistic(_ side: ProbeChartSide, _ summary: ProbeSideSummary) -> some View {
        SplitRow {
            Text(sideName(side))
        } trailing: {
            Text("\(PerformanceFormatting.number(summary.median)) \(unit) · \(localization.L(L10n.Performance.colQuartiles)) : \(PerformanceFormatting.number(summary.q1))–\(PerformanceFormatting.number(summary.q3)) · \(localization.L(L10n.Performance.colMinutes)) : \(summary.count)")
                .monospacedDigit()
        }.font(AppDesign.Font.footnote)
    }

    private func markText(_ mark: ProbeTimelineMark) -> String {
        let date = ProbeDate.parse(mark.at)?.formatted(date: .omitted, time: .shortened) ?? mark.at
        let prefix = "\(sideName(mark.side)) · \(date) · \(mark.location ?? "—")"
        if let value = mark.value { return "\(prefix) · \(PerformanceFormatting.number(value)) \(unit)" }
        let text: String
        switch mark.exclusion {
        case .existing(let reason): text = PerformanceFormatting.reasonName(reason, localization)
        case .unmatchedLocation: text = localization.L(L10n.PerformanceEvidence.unmatchedLocation)
        case .invalidMetric: text = localization.L(L10n.PerformanceEvidence.invalidMetric)
        default: text = localization.L(L10n.PerformanceEvidence.missingMetric)
        }
        return "\(prefix) · \(text)"
    }
    private var unit: String { PerformanceMetricText.unit(measure, localization) }
    private func sideName(_ side: ProbeChartSide) -> String {
        localization.L(side == .before ? L10n.Performance.before : L10n.Performance.after)
    }
    private func note(_ key: String) -> some View {
        Text(localization.L(key)).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
    }
}

struct ChartHover: View {
    let proxy: ChartProxy
    let onMove: (CGPoint) -> Void
    let onEnd: () -> Void
    let onTap: () -> Void

    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard case .active(let location) = phase,
                          let anchor = proxy.plotFrame else { onEnd(); return }
                    let frame = geometry[anchor]
                    onMove(CGPoint(x: location.x - frame.origin.x, y: location.y - frame.origin.y))
                }
                .onTapGesture { onTap() }
        }
    }
}
