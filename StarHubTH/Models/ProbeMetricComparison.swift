import Foundation

public enum ProbeMetricComparison {
    public static func summary(_ values: [Double]) -> ProbeSideSummary {
        let quartiles = ProbeStats.quartiles(values)
        return ProbeSideSummary(count: values.count, median: ProbeStats.median(values), q1: quartiles?.q1, q3: quartiles?.q3)
    }

    public static func compare(_ scope: ProbeComparisonScope, metric: ProbeMetric) -> ProbeMetricResult {
        let a = Dictionary(grouping: scope.before.comparable.kept, by: { $0.minute.location ?? "" })
        let b = Dictionary(grouping: scope.after.comparable.kept, by: { $0.minute.location ?? "" })
        let rows = scope.locations.map { location in
            let before = summary((a[location] ?? []).compactMap { metric.value($0.minute) })
            let after = summary((b[location] ?? []).compactMap { metric.value($0.minute) })
            return ProbeLocationMetricResult(location: location, before: before, after: after,
                                             outcome: outcome(before, after, metric: metric))
        }
        let eligible = rows.filter(\.admissible)
        let descriptive = eligible.isEmpty ? rows : eligible
        func average(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0) { $0 + $1 / Double(values.count) }
        }
        let before = average(descriptive.compactMap(\.before.median))
        let after = average(descriptive.compactMap(\.after.median))
        let delta = before.flatMap { a in after.map { $0 - a } }
        let percent = before.flatMap { a in a == 0 ? nil : delta.map { $0 / a * 100 } }
        let result: ProbeMetricOutcome
        if scope.incompatible { result = .incomparable }
        else if before == nil || after == nil { result = .unavailable }
        else if eligible.isEmpty { result = .insufficient }
        else { result = aggregate(eligible, metric: metric) }
        let countA = descriptive.reduce(0) { $0 + $1.before.count }
        let countB = descriptive.reduce(0) { $0 + $1.after.count }
        return ProbeMetricResult(metric: metric, before: before, after: after, delta: delta, percent: percent,
                                 outcome: result, locations: rows, keptBefore: countA, keptAfter: countB,
                                 excludedBefore: max(0, scope.before.minutes.count - countA),
                                 excludedAfter: max(0, scope.after.minutes.count - countB))
    }

    private static func outcome(_ a: ProbeSideSummary, _ b: ProbeSideSummary, metric: ProbeMetric) -> ProbeMetricOutcome {
        guard let x = a.median, let y = b.median else { return .unavailable }
        guard a.count >= 5, b.count >= 5 else { return .insufficient }
        guard abs(y - x) > abs(x) * 0.05 else { return .noClearDifference }
        guard let q1A = a.q1, let q3A = a.q3, let q1B = b.q1, let q3B = b.q3,
              q3A < q1B || q3B < q1A else { return .variable }
        if metric.isMemory { return .memoryChanged }
        return (y < x) == metric.lowerIsBetter ? .improved : .worsened
    }

    private static func aggregate(_ rows: [ProbeLocationMetricResult], metric: ProbeMetric) -> ProbeMetricOutcome {
        let positive = rows.contains { ($0.after.median ?? 0) > ($0.before.median ?? 0) && [.improved, .worsened, .memoryChanged].contains($0.outcome) }
        let negative = rows.contains { ($0.after.median ?? 0) < ($0.before.median ?? 0) && [.improved, .worsened, .memoryChanged].contains($0.outcome) }
        if positive && negative { return .mixedLocations }
        if let first = rows.first?.outcome, rows.allSatisfy({ $0.outcome == first }) { return first }
        return .variable
    }
}
