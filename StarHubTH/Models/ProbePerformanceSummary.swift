import Foundation

public struct ProbePerformanceSummary: Equatable, Sendable {
    public let side: ProbeSide
    public let metrics: [ProbeMetric: ProbeSideSummary]
    public let memory: [ProbeMemoryTrend.Segment]

    /// Tous les segments de la dernière session, sans compter deux fois les
    /// fenêtres guidées qui s'y superposent. Un changement d'inventaire reste inconnu au niveau global.
    public static func latestSession(_ sides: [ProbeSide]) -> Self? {
        let segments = sides.filter { $0.measurement == nil }
        let available = segments.isEmpty ? sides : segments
        guard let latest = available.max(by: {
            ($0.end ?? $0.minutes.last.flatMap { ProbeDate.parse($0.at) } ?? .distantPast)
                < ($1.end ?? $1.minutes.last.flatMap { ProbeDate.parse($0.at) } ?? .distantPast)
        }) else { return nil }
        let selected = available.filter { $0.session == latest.session }
        let minutes = Dictionary(selected.flatMap(\.minutes).map { ($0.at, $0) }, uniquingKeysWith: { _, b in b }).values.sorted { $0.at < $1.at }
        let kept = Dictionary(selected.flatMap(\.comparable.kept).map { ($0.minute.at, $0) }, uniquingKeysWith: { _, b in b }).values.sorted { $0.minute.at < $1.minute.at }
        let excluded = Dictionary(selected.flatMap(\.comparable.excluded).map { ($0.minute.at, $0) }, uniquingKeysWith: { _, b in b }).values.sorted { $0.minute.at < $1.minute.at }
        let counts = Dictionary(grouping: excluded, by: \.reason).mapValues(\.count)
        let side = ProbeSide(id: "session:" + latest.session, kind: .segment, session: latest.session,
            start: selected.compactMap(\.start).min() ?? minutes.first.flatMap { ProbeDate.parse($0.at) },
            end: selected.compactMap(\.end).max() ?? minutes.last.flatMap { ProbeDate.parse($0.at) },
            minutes: minutes, costs: [], inventory: selected.allSatisfy { $0.inventory == latest.inventory } ? latest.inventory : nil,
            comparable: ProbeComparableResult(kept: kept, exclusions: counts, excluded: excluded))
        return single(side)
    }

    public static func single(_ side: ProbeSide) -> Self {
        let metrics = Dictionary(uniqueKeysWithValues: ProbeMetric.allCases.map { metric in
            (metric, ProbeMetricComparison.summary(side.comparable.kept.compactMap { metric.value($0.minute) }))
        })
        return Self(side: side, metrics: metrics,
                    memory: ProbeMemoryTrend.analyze(side.comparable.kept,
                        excludedAt: side.comparable.excluded.compactMap { ProbeDate.parse($0.minute.at) }))
    }
}
