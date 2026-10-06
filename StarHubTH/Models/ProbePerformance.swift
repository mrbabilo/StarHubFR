import Foundation

/// Un moment de jeu comparable : un segment de session (parc constant) ou une
/// mesure propre, avec ses minutes, ses coûts et son inventaire résolu.
public struct ProbeSide: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case segment
        /// `crossedChangeAt` : la fenêtre traversait une coupure, les
        /// minutes d'après sont exclues (spec « Mesure propre »).
        case measurement(ProbeMeasurement, crossedChangeAt: Date?)
    }

    public let id: String
    public let kind: Kind
    public let session: String
    public let start: Date?
    public let end: Date?
    public let minutes: [ProbeMinute]
    public let costs: [ProbeModCostMinute]
    /// `nil` : sonde < 0.4.12, rien ne dit quels mods étaient chargés.
    public let inventory: [String: ProbeInventoryEntry]?
    /// Les gardes appliquées une fois, à la construction.
    public let comparable: ProbeComparableResult

    public var measurement: ProbeMeasurement? {
        if case .measurement(let value, _) = kind { return value }
        return nil
    }
}

/// Tout ce que l'onglet montre pour une paire : les vues lisent, ne calculent pas.
public struct ProbePerformanceReport: Equatable, Sendable {
    public let scope: ProbeComparisonScope
    public let metrics: [ProbeMetric: ProbeMetricResult]
    public var charts: [ProbeMetric: ProbeChartData] = [:]
    public var memoryBefore: [ProbeMemoryTrend.Segment] = []
    public var memoryAfter: [ProbeMemoryTrend.Segment] = []
    public let quality: [ProbeMetric: ProbeComparisonQuality]
    public let before: ProbeSide
    public let after: ProbeSide
    /// Minutes gardées, restreintes aux lieux communs quand il y en a assez.
    public let keptBefore: [ProbeComparableMinute]
    public let keptAfter: [ProbeComparableMinute]
    public let locationsRestricted: Bool
    public let comparison: ProbeComparison
    /// `nil` : un des deux côtés n'a pas d'inventaire — l'écran le dit, et
    /// n'annonce jamais « aucun changement ».
    public let diff: ProbeInventoryDiff?
    public let costDeltas: [ProbeCostDelta]
    public let costRows: [ProbeMeasuredCost]
    public let analysis: ProbeAnalysisResult
    public let dominantLocation: String?
}

public enum ProbePerformance {
    /// Apparier chronologiquement sans réutiliser de session. Les contrôles
    /// de qualité par métrique décideront ensuite quelles paires sont exploitables.
    public static func repetitionCandidates(_ sides: [ProbeSide], before: ProbeSide,
                                             after: ProbeSide) -> [ProbeComparisonScope] {
        guard before.inventory != nil, after.inventory != nil else { return [] }
        let ordered = sides.sorted { ($0.start ?? .distantPast, $0.id) < ($1.start ?? .distantPast, $1.id) }
        var used: Set<String> = [before.session, after.session]
        var out = [ProbeComparisonScope.make(before: before, after: after)]
        for a in ordered where a.inventory == before.inventory && !used.contains(a.session) {
            guard let b = ordered.first(where: {
                $0.inventory == after.inventory && $0.session != a.session && !used.contains($0.session)
                    && ($0.start ?? .distantPast) >= (a.start ?? .distantPast)
            }) else { continue }
            out.append(.make(before: a, after: b))
            used.insert(a.session); used.insert(b.session)
        }
        return out
    }
    /// Les côtés de toutes les sessions, du plus ancien au plus récent :
    /// chaque segment qui a des minutes, puis chaque mesure propre dans la
    /// session qui la contient. `excludingSessions` : les sessions de
    /// benchmark (`ProbeLoadRecords.benchmarkSessions`), qui ont leur propre
    /// verdict — leur minute unique n'est jamais comparable.
    public static func sides(sessions: ProbeSessions, launches: [ProbeInventoryLaunch],
                             changes: [ProbeInventoryChange],
                             measurements: [ProbeMeasurement],
                             excludingSessions: Set<String> = []) -> [ProbeSide] {
        var out: [ProbeSide] = []
        for session in sessions.sessions where !excludingSessions.contains(session.id) {
            let segments = ProbeSegments.split(session, launches: launches, changes: changes).segments
            // Les gardes tournent une fois sur la session : couper d'abord
            // ferait passer la première minute de chaque segment pour un
            // chargement (« première minute en partie »).
            let filtered = ProbeComparableMinutes.filter(session.minutes, costs: session.costs)
            func side(id: String, kind: ProbeSide.Kind, start: Date?, end: Date?, minutes: [ProbeMinute],
                      inventory: [String: ProbeInventoryEntry]?) -> ProbeSide {
                ProbeSide(id: id, kind: kind, session: session.id, start: start, end: end,
                          minutes: minutes, costs: session.costs, inventory: inventory,
                          comparable: filtered.restricted(to: minutes))
            }
            for (index, segment) in segments.enumerated() where !segment.minutes.isEmpty {
                out.append(side(id: "\(session.id)#\(index)", kind: .segment,
                                start: segment.start, end: segment.end,
                                minutes: segment.minutes, inventory: segment.inventory))
            }
            // Une mesure abandonnée n'est pas un côté (D5-A).
            for measurement in measurements where measurement.outcome != .abandoned {
                let window = ProbeMeasurementsLogic.segment(measurement, segments: segments)
                guard let first = window.minutes.first else { continue }
                // L'inventaire : celui du segment qui porte la première minute.
                let owner = segments.first { $0.minutes.contains(first) }
                out.append(side(id: "m:\(measurement.id.uuidString)",
                                kind: .measurement(measurement, crossedChangeAt: window.crossedChangeAt),
                                start: measurement.start,
                                end: measurement.end ?? window.minutes.compactMap { ProbeDate.parse($0.at) }.max(),
                                minutes: window.minutes, inventory: owner?.inventory))
            }
        }
        return out.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    /// Les deux derniers côtés dont l'inventaire diffère (une montée de la
    /// sonde compte : elle peut changer les mesures). Sans aucune différence
    /// connue : les deux derniers côtés. Moins de deux : `nil`.
    public static func defaultPair(_ sides: [ProbeSide]) -> (before: ProbeSide, after: ProbeSide)? {
        guard sides.count >= 2 else { return nil }
        // Paire guidée d'abord : la dernière mesure qui en désigne une autre
        // encore là (`PairedWith`) — le rôle ne sert qu'à l'affichage.
        for after in sides.reversed() {
            guard let target = after.measurement?.pairedWith,
                  let before = sides.first(where: { $0.measurement?.id == target }),
                  !ProbeComparisonScope.overlaps(before, after) else { continue }
            return (before, after)
        }
        for afterIndex in sides.indices.reversed() {
            let after = sides[afterIndex]
            guard let afterInventory = after.inventory else { continue }
            for beforeIndex in sides.indices[..<afterIndex].reversed() {
                if let beforeInventory = sides[beforeIndex].inventory, beforeInventory != afterInventory,
                   !ProbeComparisonScope.overlaps(sides[beforeIndex], after) {
                    return (sides[beforeIndex], after)
                }
            }
        }
        for afterIndex in sides.indices.reversed() {
            for beforeIndex in sides.indices[..<afterIndex].reversed()
                where !ProbeComparisonScope.overlaps(sides[beforeIndex], sides[afterIndex]) {
                return (sides[beforeIndex], sides[afterIndex])
            }
        }
        return nil
    }

    /// Mesure propre : deux mesures guidées stables (D5-A). Un côté bruité
    /// plafonne la confiance à « moyenne ».
    static func guidedStatus(_ a: ProbeMeasurement?, _ b: ProbeMeasurement?) -> (clean: Bool, noisy: Bool) {
        (clean: a?.outcome == .stable && b?.outcome == .stable,
         noisy: a?.outcome == .noisy || b?.outcome == .noisy)
    }

    public static func report(before: ProbeSide, after: ProbeSide,
                              repeats: [ProbeComparisonScope] = []) -> ProbePerformanceReport {
        let scope = ProbeComparisonScope.make(before: before, after: after)
        let metrics = Dictionary(uniqueKeysWithValues: ProbeMetric.allCases.map {
            ($0, ProbeMetricComparison.compare(scope, metric: $0))
        })
        let quality = metrics.mapValues { ProbeComparisonQuality.assess(scope: scope, metric: $0, repeats: repeats) }
        let locations = metrics[.frameP50]?.plottedLocations ?? []
        let shared = (a: before.comparable.kept.filter { locations.contains($0.minute.location ?? "") && ProbeMetric.frameP50.value($0.minute) != nil },
                      b: after.comparable.kept.filter { locations.contains($0.minute.location ?? "") && ProbeMetric.frameP50.value($0.minute) != nil },
                      restricted: !locations.isEmpty)
        let comparison = ProbeComparison.compare(shared.a, shared.b)
        let diff = scope.diff
        // Un côté sans coût mesuré (aucune minute comparable, ou aucune ligne
        // de coût) ne dit rien : comparé à lui, chaque mod de l'autre côté
        // passerait pour « nouveau » avec tout son coût en delta.
        let costsA = ProbeCosts.perMod(shared.a, costs: before.costs)
        let costsB = ProbeCosts.perMod(shared.b, costs: after.costs)
        let costRows = scope.incompatible ? [] : ProbeCosts.measuredRows(costsA, costsB)
        let costDeltas = costRows.compactMap { row -> ProbeCostDelta? in
            guard row.before != nil, row.after != nil else { return nil }
            return ProbeCostDelta(modId: row.modId, msPerSecondA: row.before, msPerSecondB: row.after, presence: .both)
        }
        let dominant = dominantLocation(shared.a + shared.b)
        // Mesure propre « des deux côtés » (spec §3d) : sinon aucune.
        let guided = guidedStatus(before.measurement, after.measurement)
        let measurement = guided.clean ? after.measurement : nil
        let analysis = ProbeAnalysis.analyze(ProbeAnalysisInput(
            comparison: comparison,
            diff: diff,
            costDeltas: costDeltas,
            exclusionsA: before.comparable.exclusions, exclusionsB: after.comparable.exclusions,
            locationsRestricted: shared.restricted, measurement: measurement,
            dominantLocation: dominant, noisyMeasurement: guided.noisy, metrics: metrics, quality: quality))
        var report = ProbePerformanceReport(scope: scope, metrics: metrics, quality: quality, before: before, after: after, keptBefore: shared.a,
                                      keptAfter: shared.b, locationsRestricted: shared.restricted,
                                      comparison: comparison, diff: diff, costDeltas: costDeltas, costRows: costRows,
                                      analysis: analysis, dominantLocation: dominant)
        report.charts = Dictionary(uniqueKeysWithValues: ProbeMetric.allCases.map {
            ($0, ProbeComparisonChart.data(report, measure: $0))
        })
        report.memoryBefore = ProbePerformanceSummary.single(before).memory
        report.memoryAfter = ProbePerformanceSummary.single(after).memory
        return report
    }

    // MARK: — Privé

    private static func launch(_ side: ProbeSide, _ inventory: [String: ProbeInventoryEntry])
        -> ProbeInventoryLaunch {
        ProbeInventoryLaunch(session: side.session, at: side.start, probe: nil,
                             mods: inventory.values.sorted { $0.modId < $1.modId })
    }

    /// Le lieu où il y a le plus de minutes gardées (égalité : l'ordre
    /// alphabétique, pour un résultat stable).
    private static func dominantLocation(_ minutes: [ProbeComparableMinute]) -> String? {
        var counts: [String: Int] = [:]
        for location in minutes.compactMap(\.minute.location) { counts[location, default: 0] += 1 }
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }
}
