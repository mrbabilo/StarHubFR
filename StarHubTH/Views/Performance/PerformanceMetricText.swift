import SwiftUI

enum PerformanceMetricText {
    static func name(_ metric: ProbeMetric, _ l: LocalizationStore) -> String {
        let key: String
        switch metric {
        case .frameP50: key = L10n.Performance.tileFrame
        case .frameP99: key = L10n.Performance.tileP99
        case .work: key = L10n.Performance.measureWork
        case .fps: key = L10n.Performance.measureFps
        case .workingSet: key = L10n.Performance.measureWorkingSet
        case .committed: key = L10n.Performance.measureCommitted
        case .heap: key = L10n.Performance.tileHeap
        }
        return l.L(key)
    }

    static func unit(_ metric: ProbeMetric, _ l: LocalizationStore) -> String {
        metric.isMemory ? l.L(L10n.Performance.unitMB) : metric == .fps ? "FPS" : "ms"
    }

    static func outcome(_ result: ProbeMetricOutcome, _ l: LocalizationStore) -> String {
        let key: String
        switch result {
        case .improved: key = L10n.PerformanceEvidence.improved
        case .worsened: key = L10n.PerformanceEvidence.worsened
        case .memoryChanged: key = L10n.PerformanceEvidence.memoryChanged
        case .noClearDifference: key = L10n.PerformanceEvidence.noClearDifference
        case .variable: key = L10n.PerformanceEvidence.variable
        case .mixedLocations: key = L10n.PerformanceEvidence.mixedLocations
        case .insufficient: key = L10n.PerformanceEvidence.insufficient
        case .incomparable: key = L10n.PerformanceEvidence.incomparable
        case .unavailable: key = L10n.PerformanceEvidence.unavailable
        }
        return l.L(key)
    }

    static func quality(_ level: ProbeComparisonQuality.Level, _ l: LocalizationStore) -> String {
        switch level {
        case .limited: return l.L(L10n.PerformanceEvidence.limited)
        case .usable: return l.L(L10n.PerformanceEvidence.usable)
        case .repeated: return l.L(L10n.PerformanceEvidence.repeated)
        }
    }

    static func reason(_ reason: ProbeComparisonQuality.Reason, _ l: LocalizationStore) -> String {
        let key: String
        switch reason {
        case .scopeIssue(let issue): return self.issue(issue, l)
        case .insufficientMinutes: key = L10n.PerformanceEvidence.insufficient
        case .sceneUnknown: key = L10n.PerformanceEvidence.sceneUnknown
        case .sceneChanged: key = L10n.PerformanceEvidence.sceneChanged
        case .multipleChanges: key = L10n.PerformanceEvidence.multipleChanges
        case .conflictingRepeats: key = L10n.PerformanceEvidence.conflictingRepeats
        }
        return l.L(key)
    }

    static func issue(_ issue: ProbeComparisonScope.Issue, _ l: LocalizationStore) -> String {
        let key: String
        switch issue {
        case .sameSelection: key = L10n.PerformanceEvidence.sameSelection
        case .overlappingWindows: key = L10n.PerformanceEvidence.overlappingWindows
        case .inventoryMissing: key = L10n.PerformanceEvidence.inventoryMissing
        case .noSharedLocation: key = L10n.PerformanceEvidence.noSharedLocation
        case .patchesUnknown: key = L10n.PerformanceEvidence.patchesUnknown
        case .patchesDiffer: key = L10n.PerformanceEvidence.patchesDiffer
        case .patchesMixed: key = L10n.PerformanceEvidence.patchesMixed
        case .probeVersionChanged: key = L10n.PerformanceEvidence.probeVersionChanged
        }
        return l.L(key)
    }

    static func tint(_ outcome: ProbeMetricOutcome) -> Color {
        outcome == .improved ? AppDesign.Color.success : outcome == .worsened ? AppDesign.Color.warning : .secondary
    }

    static func symbol(_ outcome: ProbeMetricOutcome) -> String {
        switch outcome {
        case .improved: return "arrow.down.right"
        case .worsened: return "arrow.up.right"
        case .noClearDifference: return "equal"
        case .memoryChanged: return "arrow.left.arrow.right"
        default: return AppDesign.Status.info.symbol
        }
    }

    static func source(_ side: ProbeSide) -> String {
        let start = side.start ?? side.minutes.first.flatMap { ProbeDate.parse($0.at) }
        let end = side.end ?? side.minutes.last.flatMap { ProbeDate.parse($0.at) }
        return [start, end].compactMap { $0?.formatted(date: .abbreviated, time: .shortened) }.joined(separator: " → ")
    }
}
