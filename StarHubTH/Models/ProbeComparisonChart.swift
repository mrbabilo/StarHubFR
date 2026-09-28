import Foundation

public enum ProbeChartSide: String, CaseIterable, Sendable { case before, after }

/// Les mesures du sélecteur de « Fluidité » : une seule à la fois, jamais
/// deux échelles sur un graphique (spec §3c).
public enum ProbeChartMeasure: String, CaseIterable, Sendable { case frameP50, frameP99, work, fps }

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
    public let side: ProbeChartSide
    public let q1: Double
    public let median: Double
    public let q3: Double
}

/// Une minute de la chronologie : gardée (valeur) ou écartée (raison, sans
/// valeur — une nuit à 13 000 ms écraserait l'échelle).
public struct ProbeTimelineMark: Identifiable, Equatable, Sendable {
    public let id: String
    public let side: ProbeChartSide
    public let minutesFromStart: Double
    public let value: Double?
    public let reason: ProbeExclusionReason?
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
    public static func value(of minute: ProbeMinute, _ measure: ProbeChartMeasure) -> Double? {
        switch measure {
        case .frameP50: return minute.frameInterval.p50
        case .frameP99: return minute.frameInterval.p99
        case .work:
            guard let update = minute.update?.p50, let draw = minute.draw?.p50 else { return nil }
            return update + draw
        case .fps: return minute.fps
        }
    }

    public static func distribution(_ report: ProbePerformanceReport, measure: ProbeChartMeasure)
        -> (points: [ProbeChartPoint], boxes: [ProbeChartBox]) {
        var points: [ProbeChartPoint] = []
        var boxes: [ProbeChartBox] = []
        for (side, kept) in [(ProbeChartSide.before, report.keptBefore), (.after, report.keptAfter)] {
            let values = kept.compactMap { item in value(of: item.minute, measure).map { (item.minute, $0) } }
            for (index, entry) in values.enumerated() {
                points.append(ProbeChartPoint(id: "\(side.rawValue)|\(entry.0.at)", side: side,
                                              at: entry.0.at, location: entry.0.location,
                                              value: entry.1, jitter: jitter(index)))
            }
            let numbers = values.map(\.1)
            if numbers.count >= 5, let median = ProbeStats.median(numbers),
               let quartiles = ProbeStats.quartiles(numbers) {
                boxes.append(ProbeChartBox(side: side, q1: quartiles.q1, median: median, q3: quartiles.q3))
            }
        }
        return (points, boxes)
    }

    /// Minutes gardées (temps de trame médian) et écartées, depuis le début
    /// de chaque côté ; `yMax` fixe la même échelle aux deux graphiques.
    public static func timeline(_ report: ProbePerformanceReport) -> (marks: [ProbeTimelineMark], yMax: Double?) {
        var marks: [ProbeTimelineMark] = []
        for (side, source) in [(ProbeChartSide.before, report.before), (.after, report.after)] {
            let start = source.start
            func offset(_ at: String) -> Double {
                guard let start, let date = ProbeDate.parse(at) else { return 0 }
                return date.timeIntervalSince(start) / 60
            }
            for item in source.comparable.kept {
                marks.append(ProbeTimelineMark(id: "\(side.rawValue)|\(item.minute.at)", side: side,
                                               minutesFromStart: offset(item.minute.at),
                                               value: item.minute.frameInterval.p50, reason: nil))
            }
            for item in source.comparable.excluded {
                marks.append(ProbeTimelineMark(id: "\(side.rawValue)|\(item.minute.at)", side: side,
                                               minutesFromStart: offset(item.minute.at),
                                               value: nil, reason: item.reason))
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
