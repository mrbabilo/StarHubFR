import Foundation

/// P1 — le verdict d'une série pilotée en une ligne, en tête de la fin de
/// série : la fluidité de B face à A, jugée sur le temps de trame (P50, P99)
/// déjà tranché par `ProbePerformance.report`. La mémoire a ses lignes à elle.
public enum GuidedPilotVerdict: Equatable, Sendable {
    /// Aucun mod n'a changé entre A et B : les écarts ne sont que du bruit
    /// (série du 2026-10-13, parc déjà sur le profil choisi).
    case identical
    case smoother, lessSmooth, mixed, noDifference, inconclusive

    public static let frameMetrics: [ProbeMetric] = [.frameP50, .frameP99]

    public static func of(_ report: ProbePerformanceReport) -> Self {
        of(changeCount: report.diff?.changes.count,
           frameOutcomes: frameMetrics.compactMap { report.metrics[$0]?.outcome })
    }

    /// `changeCount` `nil` : un côté sans inventaire — jamais « identique ».
    public static func of(changeCount: Int?, frameOutcomes: [ProbeMetricOutcome]) -> Self {
        if changeCount == 0 { return .identical }
        let better = frameOutcomes.contains(.improved), worse = frameOutcomes.contains(.worsened)
        if better && worse { return .mixed }
        if better { return .smoother }
        if worse { return .lessSmooth }
        if !frameOutcomes.isEmpty && frameOutcomes.allSatisfy({ $0 == .noClearDifference }) { return .noDifference }
        return .inconclusive
    }
}
