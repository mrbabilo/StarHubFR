import Foundation

public struct ProbeComparisonQuality: Equatable, Sendable {
    public enum Level: String, Sendable { case limited, usable, repeated }
    public enum Reason: Equatable, Sendable {
        case scopeIssue(ProbeComparisonScope.Issue), insufficientMinutes, sceneUnknown, sceneChanged
        case multipleChanges, conflictingRepeats
    }
    public let level: Level
    public let reasons: [Reason]
    public let independentPairCount: Int

    public static func assess(scope: ProbeComparisonScope, metric: ProbeMetricResult,
                              repeats: [ProbeComparisonScope]) -> Self {
        var reasons = limitations(scope, metric)
        let limited = !reasons.isEmpty
        if (scope.diff?.changes.count ?? 0) > 1 { reasons.append(.multipleChanges) }
        guard !limited else { return Self(level: .limited, reasons: reasons, independentPairCount: 0) }
        guard resolved(scope.before), resolved(scope.after) else {
            return Self(level: .usable, reasons: reasons, independentPairCount: 0)
        }
        let locations = Set(metric.locations.filter(\.admissible).map(\.location))
        var used = Set<String>()
        var results: [ProbeMetricResult] = []
        let candidates = ([scope] + repeats).sorted {
            ($0.before.start ?? .distantPast, $0.before.id, $0.after.id)
                < ($1.before.start ?? .distantPast, $1.before.id, $1.after.id)
        }
        for candidate in candidates {
            guard candidate.before.session != candidate.after.session,
                  !used.contains(candidate.before.session), !used.contains(candidate.after.session),
                  candidate.before.inventory == scope.before.inventory,
                  candidate.after.inventory == scope.after.inventory,
                  Set(candidate.before.comparable.kept.map(\.patchesMeasured)) == Set(scope.before.comparable.kept.map(\.patchesMeasured)),
                  Set(candidate.after.comparable.kept.map(\.patchesMeasured)) == Set(scope.after.comparable.kept.map(\.patchesMeasured)) else { continue }
            let result = ProbeMetricComparison.compare(candidate, metric: metric.metric)
            guard Set(result.locations.filter(\.admissible).map(\.location)) == locations,
                  limitations(candidate, result).isEmpty else { continue }
            used.insert(candidate.before.session)
            used.insert(candidate.after.session)
            results.append(result)
        }
        var opposed = false
        var allLocationsAgree = !locations.isEmpty
        for reference in metric.locations where reference.admissible {
            guard [.improved, .worsened, .memoryChanged, .noClearDifference].contains(reference.outcome) else {
                allLocationsAgree = false
                continue
            }
            let observed = results.compactMap { $0.locations.first { $0.location == reference.location } }
            let referenceDirection = direction(reference)
            if referenceDirection != 0 && observed.contains(where: { direction($0) == -referenceDirection }) {
                opposed = true
            }
            let agreeing = observed.filter {
                referenceDirection == 0 ? $0.outcome == .noClearDifference : direction($0) == referenceDirection
            }.count
            if agreeing * 3 < results.count * 2 { allLocationsAgree = false }
        }
        if opposed { reasons.append(.conflictingRepeats) }
        let repeated = results.count >= 3 && allLocationsAgree && !opposed
        return Self(level: repeated ? .repeated : .usable, reasons: reasons, independentPairCount: results.count)
    }

    private static func direction(_ row: ProbeLocationMetricResult) -> Int {
        guard [.improved, .worsened, .memoryChanged].contains(row.outcome),
              let a = row.before.median, let b = row.after.median else { return 0 }
        return b > a ? 1 : b < a ? -1 : 0
    }

    private static func resolved(_ side: ProbeSide) -> Bool {
        guard let inventory = side.inventory, !inventory.isEmpty,
              inventory.values.contains(where: { $0.modId.lowercased() == ProbeInventoryDiffRule.probeId }) else { return false }
        return inventory.values.allSatisfy { !$0.version.isEmpty && $0.configSha != nil }
    }

    private static func limitations(_ scope: ProbeComparisonScope, _ metric: ProbeMetricResult) -> [Reason] {
        var reasons = scope.issues.map(Reason.scopeIssue)
        let eligible = metric.locations.filter(\.admissible)
        if eligible.isEmpty { reasons.append(.insufficientMinutes) }
        for row in eligible {
            let a = scope.before.comparable.kept.filter { $0.minute.location == row.location && metric.metric.value($0.minute) != nil }.map(\.minute)
            let b = scope.after.comparable.kept.filter { $0.minute.location == row.location && metric.metric.value($0.minute) != nil }.map(\.minute)
            let reason: Reason?
            switch ProbeScene.assess(before: a, after: b) {
            case .unknown: reason = .sceneUnknown
            case .different: reason = .sceneChanged
            case .similar: reason = nil
            }
            if let reason, !reasons.contains(reason) { reasons.append(reason) }
        }
        return reasons
    }
}
