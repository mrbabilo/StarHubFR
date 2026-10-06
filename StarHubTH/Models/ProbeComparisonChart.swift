import Foundation

public enum ProbeChartSide: String, CaseIterable, Sendable { case before, after }

/// Les mesures du sélecteur de « Fluidité » : une seule à la fois, jamais
/// deux échelles sur un graphique (spec §3c).
public typealias ProbeChartMeasure = ProbeMetric

/// Le sens d'un écart pour le joueur, que l'écran met en couleur. Seul un
/// écart net (`.netChange`, seuil de 5 % et quartiles disjoints) ou un coût
/// au-delà du seuil de l'analyse prend un sens : le bruit reste neutre.
public enum ProbeTrend: Equatable, Sendable {
    case better, worse, neutral

    public static func of(_ verdict: ProbeMeasureComparison.Verdict, lowerIsBetter: Bool) -> ProbeTrend {
        guard case .netChange(let delta, _) = verdict, delta != 0 else { return .neutral }
        return (delta < 0) == lowerIsBetter ? .better : .worse
    }

    /// Un coût par mod (ms/s) : moins, c'est mieux ; sous le seuil de
    /// l'analyse, rien à signaler.
    public static func ofCost(_ delta: Double) -> ProbeTrend {
        guard abs(delta) > ProbeAnalysis.directCostThreshold else { return .neutral }
        return delta < 0 ? .better : .worse
    }
}

public struct ProbeChartPoint: Identifiable, Equatable, Sendable {
    public let id: String
    public let side: ProbeChartSide
    public let at: String
    public let location: String?
    public let value: Double
    /// Décalage vertical dans la rangée, ±0,3 : évite les superpositions.
    public let jitter: Double
}

public struct ProbeChartBox: Equatable, Sendable {
    public let location: String
    public let side: ProbeChartSide
    public let q1: Double
    public let median: Double
    public let q3: Double
}

/// Une minute de la chronologie : gardée (valeur) ou écartée (raison, sans
/// valeur — une nuit à 13 000 ms écraserait l'échelle).
public enum ProbeChartExclusion: Equatable, Sendable {
    case existing(ProbeExclusionReason), unmatchedLocation, missingMetric, invalidMetric
}

public struct ProbeTimelineMark: Identifiable, Equatable, Sendable {
    public let id: String
    public let side: ProbeChartSide
    public let at: String
    public let location: String?
    public let segmentId: String
    public let exclusion: ProbeChartExclusion?
    public let minutesFromStart: Double
    public let value: Double?
    public let reason: ProbeExclusionReason?
}

public struct ProbeChartData: Equatable, Sendable {
    public let points: [ProbeChartPoint]
    public let boxes: [ProbeChartBox]
    public let marks: [ProbeTimelineMark]
    public let yMax: Double?
}

public struct ProbeDumbbell: Identifiable, Equatable, Sendable {
    public var id: String { modId }
    public let modId: String
    public let before: Double?
    public let after: Double?
    public let delta: Double
}

/// Les données des graphiques de l'onglet Performances, calculées ici pour que
/// la vue ne calcule rien (spec, « Tests »).
public enum ProbeComparisonChart {
    public static func data(_ report: ProbePerformanceReport, measure: ProbeMetric) -> ProbeChartData {
        let distribution = distribution(report, measure: measure)
        let timeline = timeline(report, measure: measure)
        return ProbeChartData(points: distribution.points, boxes: distribution.boxes,
                              marks: timeline.marks, yMax: timeline.yMax)
    }

    public static func value(of minute: ProbeMinute, _ measure: ProbeMetric) -> Double? {
        measure.value(minute)
    }

    public static func distribution(_ report: ProbePerformanceReport, measure: ProbeMetric)
        -> (points: [ProbeChartPoint], boxes: [ProbeChartBox]) {
        var points: [ProbeChartPoint] = [], boxes: [ProbeChartBox] = []
        let locations = report.metrics[measure]?.plottedLocations ?? []
        for (side, source) in [(ProbeChartSide.before, report.before), (.after, report.after)] {
            let kept = source.comparable.kept.filter { locations.contains($0.minute.location ?? "") }
            for (index, item) in kept.enumerated() {
                guard let value = measure.value(item.minute) else { continue }
                points.append(ProbeChartPoint(id: "\(side.rawValue)|\(item.minute.at)", side: side,
                    at: item.minute.at, location: item.minute.location, value: value, jitter: jitter(index)))
            }
            for location in locations.sorted() {
                let values = kept.filter { $0.minute.location == location }.compactMap { measure.value($0.minute) }
                if values.count >= 5, let median = ProbeStats.median(values), let q = ProbeStats.quartiles(values) {
                    boxes.append(ProbeChartBox(location: location, side: side, q1: q.q1, median: median, q3: q.q3))
                }
            }
        }
        return (points, boxes)
    }

    public static func timeline(_ report: ProbePerformanceReport, measure: ProbeMetric = .frameP50)
        -> (marks: [ProbeTimelineMark], yMax: Double?) {
        var marks: [ProbeTimelineMark] = []
        let locations = report.metrics[measure]?.plottedLocations ?? []
        for (side, source) in [(ProbeChartSide.before, report.before), (.after, report.after)] {
            let reasons = Dictionary(source.comparable.excluded.map { ($0.minute.at, $0.reason) }, uniquingKeysWith: { a, _ in a })
            let kept = Set(source.comparable.kept.map(\.minute.at))
            let ordered = source.minutes.sorted { $0.at < $1.at }
            let start = source.start ?? ordered.compactMap { ProbeDate.parse($0.at) }.min()
            var previous: Date?, previousLocation: String?, segment = 0
            for minute in ordered {
                let date = ProbeDate.parse(minute.at)
                let exclusion: ProbeChartExclusion?
                if let reason = reasons[minute.at] { exclusion = .existing(reason) }
                else if !kept.contains(minute.at) || !locations.contains(minute.location ?? "") { exclusion = .unmatchedLocation }
                else if date == nil || !minute.wallSeconds.isFinite || minute.wallSeconds <= 0 { exclusion = .invalidMetric }
                else if measure.value(minute) == nil { exclusion = .missingMetric }
                else { exclusion = nil }
                if exclusion != nil || previous == nil || previousLocation != minute.location
                    || (date.map { $0.timeIntervalSince(previous ?? $0) > 90 } ?? true) { segment += 1 }
                let offset = date.flatMap { date in start.map { date.timeIntervalSince($0) / 60 } } ?? 0
                marks.append(ProbeTimelineMark(id: "\(side.rawValue)|\(minute.at)", side: side,
                    at: minute.at, location: minute.location, segmentId: "\(side.rawValue)|\(segment)", exclusion: exclusion,
                    minutesFromStart: offset, value: exclusion == nil ? measure.value(minute) : nil, reason: reasons[minute.at]))
                previous = exclusion == nil ? date : nil
                previousLocation = minute.location
            }
        }
        marks.sort { ($0.side.rawValue, $0.minutesFromStart) < ($1.side.rawValue, $1.minutesFromStart) }
        return (marks, marks.compactMap(\.value).max())
    }

    /// `deltas` arrive trié par impact (`ProbeCosts.delta`).
    public static func dumbbells(_ deltas: [ProbeCostDelta], limit: Int = 8)
        -> (rows: [ProbeDumbbell], others: Int) {
        let rows = deltas.prefix(limit).map {
            ProbeDumbbell(modId: $0.modId, before: $0.msPerSecondA, after: $0.msPerSecondB, delta: $0.delta)
        }
        return (Array(rows), max(deltas.count - limit, 0))
    }

    /// Déterministe (même rendu à chaque passage) : sept positions dans ±0,3.
    private static func jitter(_ index: Int) -> Double {
        Double((index * 3) % 7 - 3) / 10
    }
}
