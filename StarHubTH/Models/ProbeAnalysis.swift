import Foundation

/// Tout ce que l'analyse lit (spec §3d) : les nombres sont déjà calculés,
/// l'analyse ne fait que les lire.
public struct ProbeAnalysisInput: Sendable {
    public let comparison: ProbeComparison
    public let diff: ProbeInventoryDiff
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

    public init(comparison: ProbeComparison, diff: ProbeInventoryDiff,
                costDeltas: [ProbeCostDelta],
                exclusionsA: [ProbeExclusionReason: Int], exclusionsB: [ProbeExclusionReason: Int],
                locationsRestricted: Bool, measurement: ProbeMeasurement?,
                dominantLocation: String?, noisyMeasurement: Bool = false) {
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
    /// Cadence des ticks en pas fixe, le défaut du jeu : sert quand la sonde
    /// n'a pas relevé `Update` (lignes anciennes). En pas variable (UltraSmooth
    /// 2.3.9) la cadence mesurée de chaque côté la remplace (X117).
    static let fixedTicksPerSecond = 60.0
    /// Minutes comparables de chaque côté pour une confiance élevée.
    static let enoughMinutes = 15

    public static func analyze(_ input: ProbeAnalysisInput) -> ProbeAnalysisResult {
        // 1. Conclusion — la mesure de tête a déjà tranché (travail de trame
        // si plafond de synchro, temps de trame sinon).
        let direction: ProbeAnalysisResult.Direction
        switch input.comparison.verdict {
        case .netChange(_, let percent):
            direction = percent < 0 ? .faster(percent: -percent) : .slower(percent: percent)
        case .noise: direction = .noDifference
        case .notEnoughData: direction = .inconclusive
        }

        // 2. Confiance — une règle de « faible » l'emporte sur tout ; chaque
        // règle qui a joué laisse une preuve.
        let countA = input.comparison.frameP50.a.count
        let countB = input.comparison.frameP50.b.count
        var evidence: [ProbeAnalysisResult.Evidence] = [
            .comparableMinutes(a: countA, b: countB, sameLocations: input.locationsRestricted)
        ]
        var confidence: ProbeAnalysisResult.Confidence
        if input.measurement != nil && countA >= 5 && countB >= 5 {
            confidence = .high
            evidence.append(.cleanMeasurement)
        } else if countA >= enoughMinutes && countB >= enoughMinutes && input.locationsRestricted {
            confidence = .high
        } else if countA >= 5 && countB >= 5 {
            confidence = .medium
        } else {
            confidence = .low
        }
        if input.noisyMeasurement && confidence == .high {
            confidence = .medium
            evidence.append(.noisyMeasurement)
        }
        if !input.exclusionsA.isEmpty || !input.exclusionsB.isEmpty {
            evidence.append(.excludedMinutes(a: input.exclusionsA, b: input.exclusionsB))
        }
        let changes = input.diff.changes
        if input.diff.probeChanged {
            confidence = .low
            evidence.append(.probeChanged)
        }
        if changes.count >= 3 { confidence = .low }
        if input.comparison.patchesMismatch {
            // Enveloppes actives d'un seul côté : mesures non comparables.
            confidence = .low
            evidence.append(.envelopesAsymmetric)
        }

        // 3. Attribution — un seul changement est LA cause ; plusieurs se
        // classent par variation de leur coût direct (identifiants sans la
        // casse : mod-costs porte la casse du manifeste).
        if changes.count == 1, let only = changes.first {
            evidence.append(.singleChange(modId: only.modId))
        } else if changes.count > 1 {
            evidence.append(.changeCount(changes.count))
        }
        let changed = Set(changes.map { $0.modId.lowercased() })
        let direct = input.costDeltas
            .filter { changed.contains($0.modId.lowercased()) }
            .sorted { abs($0.delta) > abs($1.delta) }
        for delta in direct where abs(delta.delta) > 0.05 {
            evidence.append(.directCost(modId: delta.modId, deltaMsPerSecond: delta.delta))
        }

        // Part indirecte = variation du travail de trame − somme des
        // variations directes, les deux en ms par tick. Au-delà de la moitié
        // de l'écart, la cause n'est pas dans les événements des mods
        // (patches Harmony, mémoire, GC) : retour au protocole. Sans coûts
        // mesurés des deux côtés (`costDeltas` vide), rien ne se répartit.
        var indirectDominant = false
        if !input.costDeltas.isEmpty,
           case .netChange(let workDelta, _) = input.comparison.workP50.verdict, workDelta != 0 {
            // Chaque côté ramené en ms par tick à **sa** cadence : un mod
            // à 12 ms/s coûte 0,2 ms par tick à 60 ticks/s, 0,4 à 30.
            let rateA = input.comparison.updatesPerSecond.a.median.flatMap { $0 > 0 ? $0 : nil }
                ?? fixedTicksPerSecond
            let rateB = input.comparison.updatesPerSecond.b.median.flatMap { $0 > 0 ? $0 : nil }
                ?? fixedTicksPerSecond
            let directPerTick = direct.reduce(0.0) {
                $0 + ($1.msPerSecondB ?? 0) / rateB - ($1.msPerSecondA ?? 0) / rateA
            }
            let indirect = workDelta - directPerTick
            if abs(indirect) > abs(workDelta) / 2 {
                evidence.append(.indirectShare((indirect / workDelta * 100).rounded() / 100))
                indirectDominant = true
            }
        }

        // Trame nettement changée, travail de trame inchangé : le temps passe
        // hors Update/Draw (GC, synchro), là où ni les événements ni les
        // patches des mods ne tournent. Dit en preuve ; la recommandation
        // reste un geste réversible qui le vérifiera.
        if !input.comparison.vsyncLimited,
           case .netChange(_, let percent) = input.comparison.frameP50.verdict, abs(percent) >= 5,
           input.comparison.workP50.verdict == .noise {
            evidence.append(.frameWorkUnchanged)
        }

        // 4. Recommandation.
        let missing = max(enoughMinutes - min(countA, countB), 0)
        let recommendation: ProbeAnalysisResult.Recommendation
        if direction == .inconclusive || confidence == .low || indirectDominant {
            // Protocole chiffré : le lieu qui a le plus de minutes, la durée
            // qui manque pour 15 de chaque côté.
            recommendation = .rerunCleanMeasurement(location: input.dominantLocation, missingMinutes: missing)
        } else {
            recommendation = recommend(direction, changes: changes)
        }
        return ProbeAnalysisResult(direction: direction, confidence: confidence,
                                   evidence: evidence, recommendation: recommendation)
    }

    private static func recommend(_ direction: ProbeAnalysisResult.Direction,
                                  changes: [ProbeModChange]) -> ProbeAnalysisResult.Recommendation {
        let only = changes.count == 1 ? changes.first : nil
        switch direction {
        // Garde-fou : un écart sous 5 % n'est jamais une raison d'agir.
        case .slower(let percent) where percent >= 5:
            guard let only else { return changes.isEmpty ? .keep : .isolate }
            switch only.kind {
            case .added: return .disableMod(modId: only.modId)
            case .versionChanged: return .revertVersion(modId: only.modId)
            case .configChanged: return .revertConfig(modId: only.modId)
            case .removed: return .keep   // retiré et plus lent : rien à défaire
            }
        case .faster(let percent) where percent >= 5:
            return .keep
        default:
            guard let only else { return .keep }
            switch only.kind {
            case .added: return .keepNoCost(modId: only.modId)
            case .configChanged: return .configNoGain(modId: only.modId)
            default: return .keep
            }
        }
    }
}
