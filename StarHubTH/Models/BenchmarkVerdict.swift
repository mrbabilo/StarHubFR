import Foundation

public struct BenchmarkKindResult: Equatable, Sendable {
    public let verdict: ProbeLoadVerdict
    public let medianAMs: Double
    public let medianBMs: Double
    public let noisePercent: Double?
    public let thresholdPercent: Double?
}

public enum BenchmarkKindOutcome: Equatable, Sendable {
    case result(BenchmarkKindResult)
    /// Sauvegardes différentes de chaque côté, mesure des patches mêlée, ou
    /// un côté sans aucune ligne complète.
    case notComparable
}

public struct BenchmarkOutcome: Equatable, Sendable {
    public let launch: BenchmarkKindOutcome
    public let save: BenchmarkKindOutcome
}

/// Verdict d'un benchmark (spec §5) sur ses **seules** lignes, repérées par
/// `benchmarkRun` : `ProbeLoadComparison.compare` prend tout l'historique d'un
/// état et mêlerait d'autres jours. Chauffes exclues, lignes incomplètes
/// écartées, mesure des patches identique exigée.
public enum BenchmarkVerdict {
    public static func evaluate(records: [ProbeLoadRecord], runs: [BenchmarkRun], sameSave: Bool) -> BenchmarkOutcome {
        BenchmarkOutcome(launch: kind(.launch, records, runs),
                         save: sameSave ? kind(.save, records, runs) : .notComparable)
    }

    /// Un lancement réussi a écrit une ligne `save` complète sous son identifiant.
    public static func hasCompleteSave(_ records: [ProbeLoadRecord], runId: String) -> Bool {
        records.contains { $0.benchmarkRun == runId && $0.kind == .save && $0.complete }
    }

    private static func kind(_ kind: ProbeLoadRecord.Kind, _ records: [ProbeLoadRecord],
                             _ runs: [BenchmarkRun]) -> BenchmarkKindOutcome {
        var sideById: [String: BenchmarkSide] = [:]
        for run in runs where run.side.counts { sideById[run.id] = run.side }
        let mine = records.filter { record in
            record.kind == kind && record.benchmarkRun.flatMap { sideById[$0] } != nil
        }
        guard Set(mine.map(\.patchesMeasured)).count <= 1 else { return .notComparable }
        let complete = mine.filter(\.complete)
        let a = complete.filter { sideById[$0.benchmarkRun ?? ""] == .a }.map(\.totalMs)
        let b = complete.filter { sideById[$0.benchmarkRun ?? ""] == .b }.map(\.totalMs)
        guard let medianA = ProbeLoadComparison.median(a),
              let medianB = ProbeLoadComparison.median(b) else { return .notComparable }
        let noise = ProbeLoadComparison.observedNoisePercent(before: a, after: b)
        return .result(BenchmarkKindResult(
            verdict: ProbeLoadComparison.verdict(before: a, after: b),
            medianAMs: medianA, medianBMs: medianB, noisePercent: noise,
            thresholdPercent: noise.map { ProbeLoadComparison.thresholdPercent(noise: $0) }))
    }
}
