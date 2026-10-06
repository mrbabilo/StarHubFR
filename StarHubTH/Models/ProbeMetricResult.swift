import Foundation

public enum ProbeMetric: String, CaseIterable, Sendable {
    case frameP50, frameP99, work, fps, workingSet, committed, heap

    public var isMemory: Bool { self == .workingSet || self == .committed || self == .heap }
    public var lowerIsBetter: Bool { self != .fps }

    public func validated(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        if (self == .frameP50 || self == .frameP99) && value == 0 { return nil }
        return value
    }

    public func value(_ minute: ProbeMinute) -> Double? {
        guard minute.wallSeconds.isFinite, minute.wallSeconds > 0 else { return nil }
        let raw: Double?
        switch self {
        case .frameP50: raw = minute.frameInterval.p50
        case .frameP99: raw = minute.frameInterval.p99
        case .fps: raw = minute.fps
        case .workingSet: raw = minute.workingSetMB
        case .committed: raw = minute.committedMB
        case .heap: raw = minute.heapMB
        case .work:
            guard let update = validated(minute.update?.p50), let draw = validated(minute.draw?.p50) else { return nil }
            raw = update + draw
        }
        return validated(raw)
    }
}

public enum ProbeMetricOutcome: String, Equatable, Sendable {
    case improved, worsened, memoryChanged, noClearDifference, variable, mixedLocations
    case insufficient, incomparable, unavailable
}

public struct ProbeLocationMetricResult: Equatable, Sendable {
    public let location: String
    public let before: ProbeSideSummary
    public let after: ProbeSideSummary
    public let outcome: ProbeMetricOutcome
    public var admissible: Bool { before.count >= 5 && after.count >= 5 }
}

public struct ProbeMetricResult: Equatable, Sendable {
    public let metric: ProbeMetric
    public let before: Double?
    public let after: Double?
    public let delta: Double?
    public let percent: Double?
    public let outcome: ProbeMetricOutcome
    public let locations: [ProbeLocationMetricResult]
    public let keptBefore: Int
    public let keptAfter: Int
    public let excludedBefore: Int
    public let excludedAfter: Int

    /// Lieux des valeurs descriptives : lieux admissibles, ou tous les lieux
    /// communs quand l'effectif ne permet aucune comparaison.
    public var plottedLocations: Set<String> {
        let eligible = locations.filter(\.admissible)
        return Set((eligible.isEmpty ? locations : eligible).map(\.location))
    }
}
