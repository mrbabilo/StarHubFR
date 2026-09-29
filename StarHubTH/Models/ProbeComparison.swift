import Foundation

public enum ProbeStats {
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    /// Quartiles par la médiane des moitiés (méthode Tukey, médiane comprise
    /// des deux côtés pour un compte impair) : stable et suffisante pour des
    /// séries de 5 à 200 minutes.
    public static func quartiles(_ values: [Double]) -> (q1: Double, q3: Double)? {
        guard values.count >= 2 else { return nil }
        let sorted = values.sorted()
        let halfCount = (sorted.count + 1) / 2
        guard let q1 = median(Array(sorted.prefix(halfCount))),
              let q3 = median(Array(sorted.suffix(halfCount))) else { return nil }
        return (q1, q3)
    }
}

public struct ProbeSideSummary: Equatable, Sendable {
    public let count: Int
    public let median: Double?
    public let q1: Double?
    public let q3: Double?
}

public struct ProbeMeasureComparison: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        case notEnoughData
        case noise
        /// `delta` (B − A) et `percent` (de la médiane de A) arrondis à une
        /// décimale : des valeurs stables à comparer et à afficher.
        case netChange(delta: Double, percent: Double)
    }

    public let a: ProbeSideSummary
    public let b: ProbeSideSummary
    public let verdict: Verdict
}

/// Avant (A) contre après (B), sur les minutes comparables des deux côtés.
public struct ProbeComparison: Equatable, Sendable {
    public let frameP50: ProbeMeasureComparison
    public let frameP99: ProbeMeasureComparison
    /// Travail de trame : `Update.P50 + Draw.P50`.
    public let workP50: ProbeMeasureComparison
    public let fps: ProbeMeasureComparison
    public let heap: ProbeMeasureComparison
    /// Cadence des ticks (appels à `Update` par seconde) : 60 en pas fixe,
    /// celle des trames en pas variable (UltraSmooth 2.3.9, X117).
    public let updatesPerSecond: ProbeMeasureComparison
    /// Plafond de synchro verticale des deux côtés : le verdict de tête
    /// passe au travail de trame.
    public let vsyncLimited: Bool
    /// Les états de mesure des patches des deux côtés diffèrent (l'un true,
    /// l'autre false, ou un seul côté renseigné) : les trames ne sont pas
    /// comparables, le verdict de tête tombe à `.notEnoughData`.
    public let patchesMismatch: Bool
    public let verdict: ProbeMeasureComparison.Verdict

    public static func compare(_ a: [ProbeComparableMinute], _ b: [ProbeComparableMinute]) -> ProbeComparison {
        let frameP50 = compare(a.map(\.minute.frameInterval.p50), b.map(\.minute.frameInterval.p50))
        let frameP99 = compare(a.map(\.minute.frameInterval.p99), b.map(\.minute.frameInterval.p99))
        let work = compare(a.compactMap(workP50(of:)), b.compactMap(workP50(of:)))
        let fps = compare(a.map(\.minute.fps), b.map(\.minute.fps))
        let heap = compare(a.compactMap(\.minute.heapMB), b.compactMap(\.minute.heapMB))
        let updatesPerSecond = compare(a.compactMap(updatesPerSecond(of:)), b.compactMap(updatesPerSecond(of:)))

        // Plafond de synchro des deux côtés, pas forcément le même : le jeu
        // plafonne à 60 i/s, UltraSmooth le débride jusqu'à la fréquence de
        // l'écran. Un côté plafonné ne peut plus descendre : la trame ne
        // mesure plus le travail.
        let vsyncLimited = frameP50.a.median.map(isAtRefreshCeiling) == true
            && frameP50.b.median.map(isAtRefreshCeiling) == true

        // Garde « même état de la mesure des patches des deux côtés » : deux
        // inconnus (`nil` partout) s'accordent ; un seul côté renseigné ne
        // s'accorde avec rien ; sinon les états connus doivent être les mêmes.
        let patchesMismatch = Set(a.compactMap(\.patchesMeasured)) != Set(b.compactMap(\.patchesMeasured))
        let verdict = patchesMismatch ? .notEnoughData : (vsyncLimited ? work.verdict : frameP50.verdict)
        return ProbeComparison(frameP50: frameP50, frameP99: frameP99, workP50: work,
                               fps: fps, heap: heap, updatesPerSecond: updatesPerSecond,
                               vsyncLimited: vsyncLimited,
                               patchesMismatch: patchesMismatch, verdict: verdict)
    }

    /// Verdict (§2) : < 5 minutes d'un côté → pas assez ; écart > 5 % de la
    /// médiane de A **et** intervalles [Q1, Q3] disjoints → net ; sinon bruit.
    public static func compare(_ a: [Double], _ b: [Double]) -> ProbeMeasureComparison {
        func summary(_ values: [Double]) -> ProbeSideSummary {
            let quartiles = ProbeStats.quartiles(values)
            return ProbeSideSummary(count: values.count, median: ProbeStats.median(values),
                                    q1: quartiles?.q1, q3: quartiles?.q3)
        }
        let summaryA = summary(a)
        let summaryB = summary(b)
        let verdict: ProbeMeasureComparison.Verdict
        if summaryA.count < 5 || summaryB.count < 5 {
            verdict = .notEnoughData
        } else if let medianA = summaryA.median, let medianB = summaryB.median, medianA != 0,
                  let q1A = summaryA.q1, let q3A = summaryA.q3,
                  let q1B = summaryB.q1, let q3B = summaryB.q3,
                  abs(medianB - medianA) > 0.05 * abs(medianA), q3A < q1B || q3B < q1A {
            let delta = medianB - medianA
            verdict = .netChange(delta: (delta * 10).rounded() / 10,
                                 percent: (delta / medianA * 1000).rounded() / 10)
        } else {
            verdict = .noise
        }
        return ProbeMeasureComparison(a: summaryA, b: summaryB, verdict: verdict)
    }

    /// Fréquences d'écran usuelles ; ± 2 % autour de l'intervalle de trame
    /// (± 0,3 ms à 60 Hz).
    static let refreshRates: [Double] = [60, 75, 90, 100, 120, 144, 165, 240]

    /// Plafond de synchro : la période d'une fréquence usuelle (± 2 %), ou
    /// 2, 3 ou 4 périodes à 60 Hz — une trame manquée vaut deux périodes, pas
    /// un peu plus. Les multiples des autres fréquences sont écartés : leur
    /// union couvrirait la moitié des valeurs entre 10 et 70 ms.
    static func isAtRefreshCeiling(_ frameMs: Double) -> Bool {
        let periods = refreshRates.map { 1000 / $0 } + (2...4).map { Double($0) * 1000 / 60 }
        return periods.contains { abs(frameMs - $0) <= 0.02 * $0 }
    }

    private static func updatesPerSecond(of item: ProbeComparableMinute) -> Double? {
        guard let count = item.minute.update?.count, item.minute.wallSeconds > 0 else { return nil }
        return Double(count) / item.minute.wallSeconds
    }

    private static func workP50(of item: ProbeComparableMinute) -> Double? {
        guard let update = item.minute.update?.p50, let draw = item.minute.draw?.p50 else { return nil }
        return update + draw
    }
}
