import SwiftUI
import Charts

/// « Fluidité » (spec §3c.2) et « Chronologie » (§3c.3). Les graphiques
/// montrent, le tableau prouve : il reste sous chaque graphique.
struct PerformanceSmoothnessSection: View {
    @ObservedObject var localization: LocalizationStore
    let report: ProbePerformanceReport
    @State private var measure: ProbeChartMeasure = .frameP50
    @State private var hovered: ProbeChartPoint?
    /// La minute cliquée dans la distribution, marquée dans la chronologie.
    @State private var selectedAt: String?
    @State private var hoveredMark: ProbeTimelineMark?

    var body: some View {
        let distributionData = ProbeComparisonChart.distribution(report, measure: measure)
        let timelineData = ProbeComparisonChart.timeline(report)
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(localization.L(L10n.Performance.sectionSmoothness)).font(AppDesign.Font.headline(.semibold))
            // Menu, pas segments : six mesures ne tiennent plus en 420 pt —
            // « Temps de trame » et « Travail de trame » se tronquaient
            // (I-T11). Le menu garde les libellés entiers.
            Picker("", selection: $measure) {
                ForEach(ProbeChartMeasure.allCases, id: \.self) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.menu).labelsHidden().fixedSize()
            notes
            distribution(distributionData)
            table
            Text(localization.L(L10n.Performance.sectionTimeline)).font(AppDesign.Font.headline(.semibold))
            timeline(.before, data: timelineData)
            timeline(.after, data: timelineData)
            // Ligne réservée, une seule : le survol ne pousse pas « Coût par mod ».
            Text(hoveredMark.map(markText) ?? " ")
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.tail)
        }
    }

    // MARK: Distribution

    /// La mesure mémoire est-elle absente **de toutes** les minutes gardées ?
    /// Vrai sur des sessions antérieures à la sonde 0.9.11 : les champs
    /// décodent `nil`, aucun point — ce n'est pas une exclusion.
    private var memoryMissing: Bool {
        guard measure == .workingSet || measure == .committed else { return false }
        let kept = report.keptBefore + report.keptAfter
        return !kept.isEmpty && kept.allSatisfy { ProbeComparisonChart.value(of: $0.minute, measure) == nil }
    }

    @ViewBuilder
    private func distribution(_ data: (points: [ProbeChartPoint], boxes: [ProbeChartBox])) -> some View {
        if data.points.isEmpty, memoryMissing {
            // La mesure n'existait pas dans ces sessions : des exclusions de
            // trames n'expliqueraient rien — le dire, ne pas deviner (I-T11,
            // « une fonctionnalité qui ne montre rien le dit »).
            Text(localization.L(L10n.Performance.measureUnavailable))
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
        } else if data.points.isEmpty {
            exclusions   // Review Focus 1 : les raisons, pas un graphique vide.
        } else {
            Chart {
                ForEach(data.boxes, id: \.side) { box in
                    RectangleMark(xStart: .value("Q1", box.q1), xEnd: .value("Q3", box.q3),
                                  yStart: .value("Rangée", row(box.side) - 0.35),
                                  yEnd: .value("Rangée", row(box.side) + 0.35))
                        .foregroundStyle(by: .value("Côté", sideName(box.side)))
                        .opacity(0.25)
                        .cornerRadius(4)
                    RuleMark(x: .value("Médiane", box.median),
                             yStart: .value("Rangée", row(box.side) - 0.35),
                             yEnd: .value("Rangée", row(box.side) + 0.35))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(by: .value("Côté", sideName(box.side)))
                }
                ForEach(data.points) { point in
                    PointMark(x: .value("Valeur", point.value),
                              y: .value("Rangée", row(point.side) + point.jitter))
                        .symbolSize(64)   // ≈ 8 pt
                        .foregroundStyle(by: .value("Côté", sideName(point.side)))
                }
            }
            .chartForegroundStyleScale([sideName(.before): AppDesign.Chart.before,
                                        sideName(.after): AppDesign.Chart.after])
            .chartLegend(position: .top, alignment: .leading)
            .chartYScale(domain: -0.6...1.6)
            .chartXAxisLabel(unit(measure), alignment: .trailing)
            .chartYAxis {
                AxisMarks(values: [0, 1]) { value in
                    AxisValueLabel {
                        Text(value.as(Double.self) == 1 ? sideName(.before) : sideName(.after))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .chartOverlay { proxy in
                ChartHover(proxy: proxy) { local in
                    guard let x: Double = proxy.value(atX: local.x),
                          let y: Double = proxy.value(atY: local.y) else { hovered = nil; return }
                    hovered = data.points.min {
                        hypot($0.value - x, row($0.side) + $0.jitter - y)
                            < hypot($1.value - x, row($1.side) + $1.jitter - y)
                    }
                } onEnd: {
                    hovered = nil
                } onTap: {
                    selectedAt = hovered?.at
                }
            }
            .frame(height: 140)
            .accessibilityChartDescriptor(DistributionDescriptor(points: data.points, title: label(measure),
                                                                 unit: unit(measure)))
            Text(hovered.map(tooltip) ?? " ")   // réserve la ligne : pas de saut de mise en page
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.tail)
        }
    }

    /// « Avant » en haut (rangée 1), « Après » dessous (rangée 0).
    private func row(_ side: ProbeChartSide) -> Double { side == .before ? 1 : 0 }

    private func tooltip(_ point: ProbeChartPoint) -> String {
        let time = ProbeDate.parse(point.at)?.formatted(date: .omitted, time: .shortened) ?? point.at
        return "\(sideName(point.side)) · \(time) · \(point.location ?? "—") · \(number(point.value)) \(unit(measure))"
    }

    // MARK: Tableau et notes

    private var measureComparison: ProbeMeasureComparison {
        switch measure {
        case .frameP50: return report.comparison.frameP50
        case .frameP99: return report.comparison.frameP99
        case .work: return report.comparison.workP50
        case .fps: return report.comparison.fps
        case .workingSet: return report.comparison.workingSet
        case .committed: return report.comparison.committed
        }
    }

    private var table: some View {
        let m = measureComparison
        return Grid(alignment: .leading, horizontalSpacing: AppDesign.Spacing.md, verticalSpacing: 4) {
            GridRow {
                Text("")
                Text(localization.L(L10n.Performance.colMedian))
                Text(localization.L(L10n.Performance.colQuartiles))
                Text(localization.L(L10n.Performance.colMinutes))
            }
            .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            tableRow(.before, m.a, verdict: nil)
            tableRow(.after, m.b, verdict: m.verdict)
        }
        .monospacedDigit()
    }

    /// La médiane « après » prend flèche et couleur du sens quand l'écart est net.
    private func tableRow(_ side: ProbeChartSide, _ summary: ProbeSideSummary,
                          verdict: ProbeMeasureComparison.Verdict?) -> some View {
        let median = "\(number(summary.median)) \(unit(measure))"
        return GridRow {
            HStack(spacing: AppDesign.Spacing.xs) { PerformanceSideDot(side: side); Text(sideName(side)) }
            if let verdict, case .netChange(let delta, _) = verdict {
                PerformanceDelta(text: median, delta: delta,
                                 trend: ProbeTrend.of(verdict, lowerIsBetter: measure.lowerIsBetter),
                                 font: AppDesign.Font.body(.semibold))
            } else {
                Text(median)
            }
            Text("\(number(summary.q1)) – \(number(summary.q3)) \(unit(measure))")
            Text("\(summary.count)")
        }
    }

    @ViewBuilder
    private var notes: some View {
        Text(localization.L(report.locationsRestricted ? L10n.Performance.sameLocations
                                                       : L10n.Performance.differentLocations))
            .font(AppDesign.Font.footnote).foregroundColor(.secondary)
        PerformanceSceneNote(localization: localization,
                             before: report.keptBefore.map(\.minute),
                             after: report.keptAfter.map(\.minute))
        if report.comparison.vsyncLimited {
            Text(localization.L(L10n.Performance.vsync)).font(AppDesign.Font.footnote).foregroundColor(.secondary)
        }
        if report.comparison.patchesMismatch {
            Text(localization.L(L10n.Performance.patchesMismatch))
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
        }
    }

    /// Les exclusions de chaque côté, en mots (« menu ouvert ×3, nuit ×1 »).
    private var exclusions: some View {
        VStack(alignment: .leading, spacing: 2) {
            exclusionLine(.before, report.before)
            exclusionLine(.after, report.after)
        }
    }

    private func exclusionLine(_ side: ProbeChartSide, _ source: ProbeSide) -> some View {
        let prefix = source.comparable.kept.isEmpty ? localization.L(L10n.Performance.noKept) + " " : ""
        return Text("\(sideName(side)) — " + prefix
                    + String(format: localization.L(L10n.Performance.exclusionsLine),
                             exclusionText(source.comparable.exclusions)))
            .font(AppDesign.Font.footnote).foregroundColor(.secondary)
    }

    private func exclusionText(_ counts: [ProbeExclusionReason: Int]) -> String {
        counts.isEmpty ? "—" : counts.sorted { $0.value > $1.value }
            .map { "\(reasonName($0.key)) ×\($0.value)" }
            .joined(separator: ", ")
    }

    // MARK: Chronologie

    private func timeline(_ side: ProbeChartSide,
                          data: (marks: [ProbeTimelineMark], yMax: Double?)) -> some View {
        let marks = data.marks.filter { $0.side == side }
        let kept = marks.filter { $0.value != nil }
        let excluded = marks.filter { $0.value == nil }
        let top = max(data.yMax ?? 1, 1)
        let color = side == .before ? AppDesign.Chart.before : AppDesign.Chart.after
        let selected = marks.first { selectedAt != nil && $0.id == "\(side.rawValue)|\(selectedAt ?? "")" }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppDesign.Spacing.xs) {
                PerformanceSideDot(side: side)
                Text(sideName(side)).font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
            Chart {
                ForEach(kept) { mark in
                    LineMark(x: .value("Minute", mark.minutesFromStart), y: .value("ms", mark.value ?? 0))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(color)
                    PointMark(x: .value("Minute", mark.minutesFromStart), y: .value("ms", mark.value ?? 0))
                        .symbolSize(64)
                        .foregroundStyle(color)
                }
                // Écartées : une marque en pied d'axe, jamais leur valeur.
                ForEach(excluded) { mark in
                    PointMark(x: .value("Minute", mark.minutesFromStart), y: .value("ms", 0))
                        .symbol(.square).symbolSize(36)
                        .foregroundStyle(.secondary)
                }
                if let selected {
                    RuleMark(x: .value("Minute", selected.minutesFromStart))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: 0...top)   // même échelle aux deux graphiques
            .chartXAxisLabel("min", alignment: .trailing)
            .chartYAxisLabel("ms")
            .chartOverlay { proxy in
                ChartHover(proxy: proxy) { local in
                    guard let x: Double = proxy.value(atX: local.x) else { hoveredMark = nil; return }
                    hoveredMark = marks.min { abs($0.minutesFromStart - x) < abs($1.minutesFromStart - x) }
                } onEnd: {
                    hoveredMark = nil
                } onTap: {}
            }
            .frame(height: 90)
            .accessibilityChartDescriptor(TimelineDescriptor(
                marks: marks, title: sideName(side),
                labels: Dictionary(marks.compactMap { mark in mark.reason.map { (mark.id, reasonName($0)) } },
                                   uniquingKeysWith: { first, _ in first })))
        }
    }

    /// Survol d'une minute : sa valeur, ou sa raison d'exclusion (§3c.3).
    private func markText(_ mark: ProbeTimelineMark) -> String {
        let minute = "\(sideName(mark.side)) · \(Int(mark.minutesFromStart.rounded())) min"
        if let value = mark.value { return "\(minute) · \(number(value)) ms" }
        return "\(minute) · \(mark.reason.map(reasonName) ?? "—")"
    }

    // MARK: Libellés

    private func sideName(_ side: ProbeChartSide) -> String {
        localization.L(side == .before ? L10n.Performance.before : L10n.Performance.after)
    }

    private func label(_ measure: ProbeChartMeasure) -> String {
        switch measure {
        case .frameP50: return localization.L(L10n.Performance.measureFrame)
        case .frameP99: return localization.L(L10n.Performance.measureP99)
        case .work: return localization.L(L10n.Performance.measureWork)
        case .fps: return localization.L(L10n.Performance.measureFps)
        case .workingSet: return localization.L(L10n.Performance.measureWorkingSet)
        case .committed: return localization.L(L10n.Performance.measureCommitted)
        }
    }

    /// Unité de la mesure : identique en français et en anglais.
    private func unit(_ measure: ProbeChartMeasure) -> String {
        measure == .fps ? "FPS" : (measure == .workingSet || measure == .committed ? "Mo" : "ms")
    }

    private func reasonName(_ reason: ProbeExclusionReason) -> String {
        PerformanceFormatting.reasonName(reason, localization)
    }

    private func number(_ value: Double?) -> String {
        PerformanceFormatting.number(value)
    }
}

/// Le calque de survol commun aux graphiques : la position **dans la zone de
/// tracé** (chaque graphique la convertit, axe numérique ou catégoriel), la
/// fin du survol, le clic.
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

/// Audio graphs de macOS (VoiceOver) : un point par minute, rangée 1 = avant.
private struct DistributionDescriptor: AXChartDescriptorRepresentable {
    let points: [ProbeChartPoint]
    let title: String
    let unit: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = points.map(\.value)
        let x = AXNumericDataAxisDescriptor(title: title, range: (values.min() ?? 0)...(values.max() ?? 1),
                                            gridlinePositions: []) { [unit] in
            "\($0.formatted(.number.precision(.fractionLength(1)))) \(unit)"
        }
        let y = AXNumericDataAxisDescriptor(title: "", range: 0...1, gridlinePositions: []) {
            $0 >= 0.5 ? ProbeChartSide.before.rawValue : ProbeChartSide.after.rawValue
        }
        let series = ProbeChartSide.allCases.map { side in
            AXDataSeriesDescriptor(name: side.rawValue, isContinuous: false,
                                   dataPoints: points.filter { $0.side == side }.map {
                                       AXDataPoint(x: $0.value, y: side == .before ? 1 : 0, label: $0.location)
                                   })
        }
        return AXChartDescriptor(title: title, summary: nil, xAxis: x, yAxis: y,
                                 additionalAxes: [], series: series)
    }
}

private struct TimelineDescriptor: AXChartDescriptorRepresentable {
    let marks: [ProbeTimelineMark]
    let title: String
    /// Raison d'exclusion déjà traduite, par identifiant de minute.
    let labels: [String: String]

    func makeChartDescriptor() -> AXChartDescriptor {
        let minutes = marks.map(\.minutesFromStart)
        let low = min(minutes.min() ?? 0, 0), high = max(minutes.max() ?? 1, 1)
        let x = AXNumericDataAxisDescriptor(title: "min", range: low...high, gridlinePositions: []) {
            "\(Int($0.rounded())) min"
        }
        let top = max(marks.compactMap(\.value).max() ?? 1, 1)
        let y = AXNumericDataAxisDescriptor(title: "ms", range: 0...top, gridlinePositions: []) {
            "\(Int($0.rounded())) ms"
        }
        let series = AXDataSeriesDescriptor(name: title, isContinuous: true, dataPoints: marks.map {
            AXDataPoint(x: $0.minutesFromStart, y: $0.value ?? 0, label: labels[$0.id])
        })
        return AXChartDescriptor(title: title, summary: nil, xAxis: x, yAxis: y,
                                 additionalAxes: [], series: [series])
    }
}
