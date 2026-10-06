import Foundation

/// Tout ce que l'analyse lit (spec §3d) : les nombres sont déjà calculés,
/// l'analyse ne fait que les lire.
public struct ProbeAnalysisInput: Sendable {
    public let metrics: [ProbeMetric: ProbeMetricResult]
    public let quality: [ProbeMetric: ProbeComparisonQuality]
    public let comparison: ProbeComparison
    public let diff: ProbeInventoryDiff?
    public let costDeltas: [ProbeCostDelta]
    public let exclusionsA: [ProbeExclusionReason: Int]
    public let exclusionsB: [ProbeExclusionReason: Int]
    public let locationsRestricted: Bool
    public let measurement: ProbeMeasurement?
    /// Lieu où il y a le plus de minutes gardées (calcul de l'appelant) :
    /// le protocole de « refaire une mesure propre » le nomme.
    public let dominantLocation: String?
    /// Un côté est une mesure guidée bruitée : confiance plafonnée à « moyenne » (D5-A).
    public let noisyMeasurement: Bool

    public init(comparison: ProbeComparison, diff: ProbeInventoryDiff?,
                costDeltas: [ProbeCostDelta],
                exclusionsA: [ProbeExclusionReason: Int], exclusionsB: [ProbeExclusionReason: Int],
                locationsRestricted: Bool, measurement: ProbeMeasurement?,
                dominantLocation: String?, noisyMeasurement: Bool = false,
                metrics: [ProbeMetric: ProbeMetricResult] = [:],
                quality: [ProbeMetric: ProbeComparisonQuality] = [:]) {
        self.metrics = metrics
        self.quality = quality
        self.comparison = comparison
        self.diff = diff
        self.costDeltas = costDeltas
        self.exclusionsA = exclusionsA
        self.exclusionsB = exclusionsB
        self.locationsRestricted = locationsRestricted
        self.measurement = measurement
        self.dominantLocation = dominantLocation
        self.noisyMeasurement = noisyMeasurement
    }
}

public struct ProbeAnalysisResult: Equatable, Sendable {
    public enum Direction: Equatable, Sendable {
        case slower(percent: Double)
        case faster(percent: Double)
        case noDifference
        case inconclusive
    }
    public enum Confidence: Equatable, Sendable { case high, medium, low }
    /// Une règle qui a joué ; l'écran (plan 4) en fait des lignes L10n. La
    /// recommandation ne dit rien que ces lignes ne montrent.
    public enum Evidence: Equatable, Sendable {
        case comparableMinutes(a: Int, b: Int, sameLocations: Bool)
        case singleChange(modId: String)
        case changeCount(Int)
        case directCost(modId: String, deltaMsPerSecond: Double)
        case indirectShare(Double)
        case probeChanged
        case envelopesAsymmetric
        /// Mesure propre, au moins 5 minutes de chaque côté.
        case cleanMeasurement
        /// Un côté est une mesure guidée bruitée (D5-A).
        case noisyMeasurement
        /// Minutes écartées, par raison, de chaque côté.
        case excludedMinutes(a: [ProbeExclusionReason: Int], b: [ProbeExclusionReason: Int])
        /// Trame nettement changée, travail de trame inchangé.
        case frameWorkUnchanged
    }
    /// Une action principale, toujours réversible (jamais de suppression).
    public enum Recommendation: Equatable, Sendable {
        case disableMod(modId: String)
        case revertVersion(modId: String)
        case revertConfig(modId: String)
        case keep
        case keepNoCost(modId: String)
        case configNoGain(modId: String)
        case isolate
        case rerunCleanMeasurement(location: String?, missingMinutes: Int)
    }
    public let direction: Direction
    public let confidence: Confidence
    public let evidence: [Evidence]
    public let recommendation: Recommendation
}

/// Règles explicables et déterministes (spec §3d) : mêmes données, même
/// réponse. Fonction pure.
public enum ProbeAnalysis {
    public static let directCostThreshold = 0.05

    public static func analyze(_ input: ProbeAnalysisInput) -> ProbeAnalysisResult {
        let metric = input.metrics[.frameP50]
        let quality = input.quality[.frameP50]
        let direction: ProbeAnalysisResult.Direction
        switch metric?.outcome {
        case .improved: direction = metric?.percent.map { .faster(percent: abs($0)) } ?? .inconclusive
        case .worsened: direction = metric?.percent.map { .slower(percent: abs($0)) } ?? .inconclusive
        case .noClearDifference: direction = .noDifference
        default: direction = .inconclusive
        }
        let confidence: ProbeAnalysisResult.Confidence
        switch quality?.level {
        case .repeated: confidence = .high
        case .usable: confidence = .medium
        default: confidence = .low
        }
        var evidence: [ProbeAnalysisResult.Evidence] = [
            .comparableMinutes(a: metric?.keptBefore ?? 0, b: metric?.keptAfter ?? 0,
                               sameLocations: input.locationsRestricted)
        ]
        if !input.exclusionsA.isEmpty || !input.exclusionsB.isEmpty {
            evidence.append(.excludedMinutes(a: input.exclusionsA, b: input.exclusionsB))
        }
        let changes = input.diff?.changes ?? []
        if let only = changes.first, changes.count == 1 { evidence.append(.singleChange(modId: only.modId)) }
        else if !changes.isEmpty { evidence.append(.changeCount(changes.count)) }
        if input.diff?.probeChanged == true { evidence.append(.probeChanged) }
        if input.comparison.patchesMismatch { evidence.append(.envelopesAsymmetric) }
        let changed = Set(changes.map { $0.modId.lowercased() })
        for cost in input.costDeltas.sorted(by: { abs($0.delta) > abs($1.delta) })
            where changed.contains(cost.modId.lowercased()) && abs(cost.delta) > directCostThreshold {
            evidence.append(.directCost(modId: cost.modId, deltaMsPerSecond: cost.delta))
        }
        let counts = metric?.locations.map { min($0.before.count, $0.after.count) } ?? []
        let missing = max(0, 5 - (counts.max() ?? 0))
        let recommendation: ProbeAnalysisResult.Recommendation
        if confidence == .low || direction == .inconclusive {
            recommendation = .rerunCleanMeasurement(location: input.dominantLocation, missingMinutes: missing)
        } else if changes.count > 1 {
            recommendation = .isolate
        } else if quality?.level != .repeated && direction != .noDifference {
            recommendation = .rerunCleanMeasurement(location: input.dominantLocation, missingMinutes: 0)
        } else if case .slower = direction, let only = changes.first {
            switch only.kind {
            case .added: recommendation = .disableMod(modId: only.modId)
            case .versionChanged: recommendation = .revertVersion(modId: only.modId)
            case .configChanged: recommendation = .revertConfig(modId: only.modId)
            case .removed: recommendation = .keep
            }
        } else { recommendation = .keep }
        return ProbeAnalysisResult(direction: direction, confidence: confidence,
                                   evidence: evidence, recommendation: recommendation)
    }
}
