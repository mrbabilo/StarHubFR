import Foundation

/// Un coût dans une phase de chargement : un gestionnaire d'événement (`event`),
/// un rappel d'asset (`asset`), une section de pack Content Patcher (`pack`)
/// ou un patch Harmony (`patch`), en temps propre.
public struct ProbeLoadCost: Equatable, Sendable {
    public enum Kind: String, Sendable { case event, asset, pack, patch }
    public let mod: String
    public let kind: Kind
    public let label: String
    public let ms: Double
    public let allocMb: Double
    public let calls: Int

    public init(mod: String, kind: Kind, label: String, ms: Double, allocMb: Double, calls: Int) {
        self.mod = mod
        self.kind = kind
        self.label = label
        self.ms = ms
        self.allocMb = allocMb
        self.calls = calls
    }
}

/// Un jalon atteint, en millisecondes depuis le début du lancement (`L0`) ou
/// du clic sur la sauvegarde (`S0`).
public struct ProbeLoadMilestone: Equatable, Sendable {
    public let name: String
    public let ms: Double

    public init(name: String, ms: Double) {
        self.name = name
        self.ms = ms
    }
}

/// Ce qui a coûté entre deux jalons consécutifs.
public struct ProbeLoadPhase: Equatable, Sendable {
    public let from: String
    public let to: String
    public let ms: Double
    public let costs: [ProbeLoadCost]

    public init(from: String, to: String, ms: Double, costs: [ProbeLoadCost]) {
        self.from = from
        self.to = to
        self.ms = ms
        self.costs = costs
    }
}

/// Une ligne de `loads.jsonl` (sonde 0.6.0, D5-B) : un lancement ou un
/// chargement de sauvegarde, jalonné, avec le coût par mod et par pack entre
/// deux jalons. Décodage tolérant ligne à ligne : une ligne illisible est
/// comptée, jamais le fichier entier.
public struct ProbeLoadRecord: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case launch, save }

    public struct Health: Equatable, Sendable {
        public let packSeam: String
        public let assetHook: String
        public let loadHook: String
        public let offThreadSections: Int

        public init(packSeam: String, assetHook: String, loadHook: String, offThreadSections: Int) {
            self.packSeam = packSeam
            self.assetHook = assetHook
            self.loadHook = loadHook
            self.offThreadSections = offThreadSections
        }
    }

    public struct Final: Equatable, Sendable {
        public let name: String
        public let ms: Double
        public let menu: String?

        public init(name: String, ms: Double, menu: String?) {
            self.name = name
            self.ms = ms
            self.menu = menu
        }
    }

    public var id: String { "\(session)|\(kind.rawValue)|\(atText)" }
    public let kind: Kind
    public let session: String
    public let atText: String
    public let at: Date?
    public let probeVersion: String
    public let complete: Bool
    public let reload: Bool
    public let saveName: String?
    public let patchesMeasured: Bool
    public let saveBytes: Int64?
    public let saveDate: String?
    public let milestones: [ProbeLoadMilestone]
    public let phases: [ProbeLoadPhase]
    public let final: Final?
    public let health: Health
    /// Benchmark automatique : identifiant du lancement sous plan, sinon nil.
    public let benchmarkRun: String?
    /// Total comparé : dernier jalon de phase (`L4` ou `S9`) — `S10` attend un
    /// humain et n'entre jamais dans une comparaison.
    public let totalMs: Double

    public init(kind: Kind, session: String, atText: String, at: Date?, probeVersion: String,
                complete: Bool, reload: Bool, saveName: String?, patchesMeasured: Bool,
                saveBytes: Int64?, saveDate: String?, milestones: [ProbeLoadMilestone],
                phases: [ProbeLoadPhase], final: Final?, health: Health, benchmarkRun: String? = nil) {
        self.kind = kind
        self.session = session
        self.atText = atText
        self.at = at
        self.probeVersion = probeVersion
        self.complete = complete
        self.reload = reload
        self.saveName = saveName
        self.patchesMeasured = patchesMeasured
        self.saveBytes = saveBytes
        self.saveDate = saveDate
        self.milestones = milestones
        self.phases = phases
        self.final = final
        self.health = health
        self.benchmarkRun = benchmarkRun
        self.totalMs = milestones.last { $0.name == "L4" || $0.name == "S9" }?.ms
            ?? milestones.last?.ms ?? 0
    }
}

public enum ProbeLoadRecords {
    /// Vrai si `version` (chiffres séparés par des points, rien d'autre) vaut au moins `floor`.
    public static func version(_ version: String?, atLeast floor: [Int]) -> Bool {
        guard let version else { return false }
        let raw = version.split(separator: ".")
        let parts = raw.compactMap { Int($0) }
        guard parts.count == raw.count, !parts.isEmpty else { return false }
        for i in 0..<max(parts.count, floor.count) {
            let p = i < parts.count ? parts[i] : 0
            let f = i < floor.count ? floor[i] : 0
            if p != f { return p > f }
        }
        return true
    }

    /// Vrai si une sonde de cette version écrit `loads.jsonl` (0.6.0 et plus).
    public static func writesLoads(probeVersion: String?) -> Bool {
        version(probeVersion, atLeast: [0, 6, 0])
    }

    /// Les lignes des sessions ordinaires : un benchmark a son propre verdict,
    /// ses chauffes et ses lancements n'entrent pas dans la carte.
    public static func manual(_ records: [ProbeLoadRecord]) -> [ProbeLoadRecord] {
        records.filter { $0.benchmarkRun == nil }
    }

    public static func decode(_ data: Data) -> (records: [ProbeLoadRecord], unreadable: Int) {
        let (lines, unreadable) = ProbeJSON.lines(DecodedLine.self, from: data)
        return (lines.compactMap(convert), unreadable)
    }

    // MARK: — Privé

    /// Calqué sur le JSON de la sonde (`System.Text.Json`, PascalCase) ;
    /// `ProbeJSON.decoder()` passe la première lettre en minuscule.
    private struct DecodedLine: Decodable {
        var kind: String
        var session: String
        var at: String
        var probeVersion: String
        var complete: Bool
        var reload: Bool
        var saveName: String?
        var patchesMeasured: Bool
        var saveBytes: Int64?
        var saveDate: String?
        var milestones: [DecodedMilestone]
        var phases: [DecodedPhase]
        var final: DecodedFinal?
        var health: DecodedHealth
        var benchmarkRun: String?

        struct DecodedMilestone: Decodable {
            var name: String
            var ms: Double
        }

        struct DecodedPhase: Decodable {
            var from: String
            var to: String
            var ms: Double
            var costs: [DecodedCost]
        }

        struct DecodedCost: Decodable {
            var mod: String
            var kind: String
            var label: String
            var ms: Double
            var allocMb: Double
            var calls: Int
        }

        struct DecodedFinal: Decodable {
            var name: String
            var ms: Double
            var menu: String?
        }

        struct DecodedHealth: Decodable {
            var packSeam: String
            var assetHook: String
            var loadHook: String
            var offThreadSections: Int
        }
    }

    private static func convert(_ line: DecodedLine) -> ProbeLoadRecord? {
        guard let kind = ProbeLoadRecord.Kind(rawValue: line.kind) else { return nil }
        let phases = line.phases.map { phase in
            ProbeLoadPhase(from: phase.from, to: phase.to, ms: phase.ms,
                           costs: phase.costs.compactMap { cost in
                               guard let kind = ProbeLoadCost.Kind(rawValue: cost.kind) else { return nil }
                               return ProbeLoadCost(mod: cost.mod, kind: kind, label: cost.label,
                                                    ms: cost.ms, allocMb: cost.allocMb, calls: cost.calls)
                           })
        }
        return ProbeLoadRecord(
            kind: kind, session: line.session, atText: line.at, at: ProbeDate.parse(line.at),
            probeVersion: line.probeVersion, complete: line.complete, reload: line.reload,
            saveName: line.saveName, patchesMeasured: line.patchesMeasured,
            saveBytes: line.saveBytes, saveDate: line.saveDate,
            milestones: line.milestones.map { ProbeLoadMilestone(name: $0.name, ms: $0.ms) },
            phases: phases,
            final: line.final.map { ProbeLoadRecord.Final(name: $0.name, ms: $0.ms, menu: $0.menu) },
            health: ProbeLoadRecord.Health(packSeam: line.health.packSeam, assetHook: line.health.assetHook,
                                           loadHook: line.health.loadHook,
                                           offThreadSections: line.health.offThreadSections),
            benchmarkRun: line.benchmarkRun)
    }
}
