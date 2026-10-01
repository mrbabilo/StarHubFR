import Foundation

/// D5-C — ce qu'une source (un segment de jeu, un lancement, un chargement de
/// sauvegarde) a mesuré pour un mod. Valeurs absolues **et** parts calculées
/// contre les totaux de cette source, sonde exclue : la part dit « part du
/// parc de ce jour-là », stable quand le parc change ensuite.
public struct ModImpactSample: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case inGame, launch, save }

    public static let shareFloor = 0.001
    public static let spikeFloor = 0.01

    public let sourceId: String
    public let kind: Kind
    public let date: Date
    /// Version du mod au moment de la mesure ; nil si l'inventaire manque.
    public let version: String?
    // En jeu
    public let msPerSecond: Double?
    public let maxMs: Double?
    public let allocMBPerMinute: Double?
    public let msPerFrame: Double?
    /// ms/s du mod ÷ travail de trame par seconde.
    public let frameWorkShare: Double?
    public let patchesMeasured: Bool?
    // Chargement
    public let ms: Double?
    // Parts
    public let fpsShare: Double?
    public let spikeShare: Double?
    public let allocShare: Double?
    /// Lancement ou sauvegarde, selon `kind`.
    public let loadShare: Double?

    /// Toutes les parts mesurées sous leur plancher (ou aucune mesurée).
    public var isNegligible: Bool {
        let shares = [fpsShare, allocShare, loadShare].compactMap { $0 }
        return shares.allSatisfy { $0 < Self.shareFloor } && (spikeShare ?? 0) < Self.spikeFloor
    }
}

public struct ModImpactSource: Equatable, Sendable {
    public let id: String
    public let kind: ModImpactSample.Kind
    public let date: Date
    /// Par identifiant tel qu'écrit par la sonde.
    public let samples: [String: ModImpactSample]
    /// Le coût de la sonde elle-même (en jeu), exclue des parts.
    public let probeMsPerFrame: Double?
}

public enum ModImpactSources {
    public static let minimumKeptMinutes = 5
    public static let minimumProbe = [0, 9, 0]

    static func isProbe(_ id: String) -> Bool {
        id.caseInsensitiveCompare(BenchmarkSides.probeId) == .orderedSame
    }

    /// Versions par identifiant en minuscules (la sonde et le registre
    /// n'écrivent pas toujours la même casse).
    static func versionsByModId(_ entries: [String: ProbeInventoryEntry]?) -> [String: String] {
        var out: [String: String] = [:]
        for entry in (entries ?? [:]).values { out[entry.modId.lowercased()] = entry.version }
        return out
    }

    /// Un segment d'au moins `minimumKeptMinutes` minutes gardées.
    public static func inGame(_ side: ProbeSide) -> ModImpactSource? {
        guard case .segment = side.kind, side.comparable.kept.count >= minimumKeptMinutes,
              let date = side.start ?? ProbeDate.parse(side.session) else { return nil }
        let costs = ProbeCosts.segmentCosts(side.comparable.kept, costs: side.costs)
        let mods = costs.mods.filter { !isProbe($0.key) }
        let sumMs = mods.values.map(\.msPerSecond).reduce(0, +)
        guard sumMs > 0 else { return nil }
        let maxSpike = mods.values.map(\.maxMs).max() ?? 0
        let sumAlloc = mods.values.map(\.allocMBPerMinute).reduce(0, +)
        let workPerSecond = costs.seconds > 0 ? costs.frameWorkMs / costs.seconds : 0
        let patched: Bool? = costs.lines > 0 ? costs.patchesMeasuredLines == costs.lines : nil
        let versions = versionsByModId(side.inventory)
        var samples: [String: ModImpactSample] = [:]
        for (id, s) in mods {
            samples[id] = ModImpactSample(
                sourceId: side.id, kind: .inGame, date: date, version: versions[id.lowercased()],
                msPerSecond: s.msPerSecond, maxMs: s.maxMs, allocMBPerMinute: s.allocMBPerMinute,
                msPerFrame: costs.fps > 0 ? s.msPerSecond / costs.fps : nil,
                frameWorkShare: workPerSecond > 0 ? s.msPerSecond / workPerSecond : nil,
                patchesMeasured: patched, ms: nil,
                fpsShare: s.msPerSecond / sumMs,
                spikeShare: maxSpike > 0 ? s.maxMs / maxSpike : nil,
                allocShare: sumAlloc > 0 ? s.allocMBPerMinute / sumAlloc : nil,
                loadShare: nil)
        }
        let probe = costs.mods.first { isProbe($0.key) }?.value
        return ModImpactSource(id: side.id, kind: .inGame, date: date, samples: samples,
                               probeMsPerFrame: probe.flatMap { costs.fps > 0 ? $0.msPerSecond / costs.fps : nil })
    }

    /// Froid = premier lancement après **un** des démarrages connus.
    /// `ProbeLoadComparison.isCold` ne voit que le démarrage courant : le
    /// premier lancement d'un démarrage passé y redevient « chaud ».
    public static func isCold(_ record: ProbeLoadRecord, among records: [ProbeLoadRecord], boots: [Date]) -> Bool {
        boots.contains { ProbeLoadComparison.isCold(record, among: records, coldBefore: $0) }
    }

    /// Un lancement ou un chargement de sauvegarde hors benchmark : complet, chaud, sonde
    /// ≥ 0.9.0 ; un lancement exige la sonde en tête (sinon le chargement des
    /// mods d'avant elle manque).
    public static func load(_ record: ProbeLoadRecord, launches: [ProbeInventoryLaunch],
                            isCold: Bool) -> ModImpactSource? {
        // Un benchmark tourne sur un parc réduit : ses parts ne disent rien du
        // parc réel (ses sessions en jeu sont déjà écartées).
        guard record.benchmarkRun == nil, record.complete, !isCold, let date = record.at,
              ProbeLoadRecords.version(record.probeVersion, atLeast: minimumProbe) else { return nil }
        if record.kind == .launch, record.probeLoadsFirst != true { return nil }
        let kind: ModImpactSample.Kind = record.kind == .launch ? .launch : .save
        let totals = ProbeLoadBreakdown.of(record).mods.filter { !isProbe($0.mod) }
        let sum = totals.map(\.ms).reduce(0, +)
        guard sum > 0 else { return nil }
        let versions = versionsByModId(launches.last { $0.session == record.session }?.byModId)
        var samples: [String: ModImpactSample] = [:]
        for total in totals {
            samples[total.mod] = ModImpactSample(
                sourceId: record.id, kind: kind, date: date, version: versions[total.mod.lowercased()],
                msPerSecond: nil, maxMs: nil, allocMBPerMinute: nil, msPerFrame: nil,
                frameWorkShare: nil, patchesMeasured: nil, ms: total.ms,
                fpsShare: nil, spikeShare: nil, allocShare: nil, loadShare: total.ms / sum)
        }
        return ModImpactSource(id: record.id, kind: kind, date: date, samples: samples, probeMsPerFrame: nil)
    }
}
