import Foundation

/// Une étape d'un chargement (D5-B) : sa durée, ce que les mods y ont coûté
/// (temps propre, trié), et la part non attribuée — jeu, SMAPI, et tout code
/// de mod hors des points d'accroche.
public struct ProbeLoadSpan: Equatable, Sendable, Identifiable {
    public enum Name: String, Sendable {
        case smapiAndMods      // L0 → L2 (L0→L1 et L1→L2 fusionnés : non ventilés)
        case gameLaunched      // L2 → L3
        case firstTick         // L3 → L4
        case readSave          // S0 → S1
        case addLocations      // S1 → S2
        case basicInfo         // S2 → S3
        case loadLocations     // S3 → S4
        case preload           // S4 → S5
        case loaded            // S5 → S6
        case ready             // S6 → S7
        case saveLoaded        // S7 → S8
        case dayStarted        // S8 → S9
        case waitingForPlayer  // S9 → S10 (jamais compté dans le total)
    }

    public var id: Name { name }
    public let name: Name
    public let ms: Double
    public let attributedMs: Double
    public let costs: [ProbeLoadCost]

    public init(name: Name, ms: Double, attributedMs: Double, costs: [ProbeLoadCost]) {
        self.name = name
        self.ms = ms
        self.attributedMs = attributedMs
        self.costs = costs
    }

    public var unattributedMs: Double { max(0, ms - attributedMs) }
}

/// Combien de chargements de mods la sonde a vus, sur combien à voir
/// (registre moins la sonde). `nil` avant la sonde 0.9.0.
public struct LoadCoverage: Equatable, Sendable {
    public let seen: Int
    public let total: Int

    public init(seen: Int, total: Int) { self.seen = seen; self.total = total }
}

/// Le total d'un mod sur tous les spans comparés d'un chargement. Un coût de
/// pack compte pour son pack, jamais pour Content Patcher.
public struct ProbeLoadModTotal: Equatable, Sendable, Identifiable {
    public var id: String { mod }
    public let mod: String
    public let ms: Double
    public let isPack: Bool
    /// Dont démarrage (`entry`, sonde 0.8.0).
    public let entryMs: Double
    /// Dont chargement (`load`, sonde 0.9.0).
    public let loadMs: Double

    public init(mod: String, ms: Double, isPack: Bool, entryMs: Double = 0, loadMs: Double = 0) {
        self.mod = mod
        self.ms = ms
        self.isPack = isPack
        self.entryMs = entryMs
        self.loadMs = loadMs
    }
}

/// Un enregistrement de `loads.jsonl` découpé en étapes nommées, avec le
/// classement des mods et packs les plus lourds. Pur, testé sur la fixture
/// écrite par le modèle de la sonde.
public struct ProbeLoadBreakdown: Equatable, Sendable {
    public let record: ProbeLoadRecord
    public let spans: [ProbeLoadSpan]
    /// Cinq au plus, hors `waitingForPlayer`.
    public let top: [ProbeLoadModTotal]
    public let packSeamMissing: Bool
    public let assetHookMissing: Bool
    /// Sonde 0.8.0 : durée de la boucle de démarrage des mods (lancement).
    public let entryLoopMs: Double?
    /// Lancement d'une sonde qui a l'accroche mais ne l'a pas vue tirer.
    public let entryHookMissing: Bool
    /// Sonde 0.9.0 : durée de la boucle de chargement des mods (lancement).
    public let loadLoopMs: Double?
    /// Combien de chargements vus sur combien à voir ; nil avant 0.9.0.
    public let loadCoverage: LoadCoverage?
    /// La sonde est la première du registre de SMAPI ; nil avant 0.9.0.
    public let probeLoadsFirst: Bool?

    /// Couples `(from, to)` connus. Un couple inconnu (jalon d'une sonde
    /// future) est ignoré.
    private static let saveNames: [String: ProbeLoadSpan.Name] = [
        "S0>S1": .readSave, "S1>S2": .addLocations, "S2>S3": .basicInfo,
        "S3>S4": .loadLocations, "S4>S5": .preload, "S5>S6": .loaded,
        "S6>S7": .ready, "S7>S8": .saveLoaded, "S8>S9": .dayStarted,
    ]
    private static let launchNames: [String: ProbeLoadSpan.Name] = [
        "L2>L3": .gameLaunched, "L3>L4": .firstTick,
    ]

    public static func of(_ record: ProbeLoadRecord) -> ProbeLoadBreakdown {
        var spans: [ProbeLoadSpan] = []
        if record.kind == .launch {
            // L0→L1 et L1→L2 : SMAPI et l'Entry des mods, non ventilés.
            let head = record.phases.filter { $0.from == "L0" || $0.from == "L1" }
            spans.append(ProbeLoadSpan(name: .smapiAndMods, ms: head.reduce(0) { $0 + $1.ms },
                                       attributedMs: head.reduce(0) { $0 + $1.costs.map(\.ms).reduce(0, +) },
                                       costs: head.flatMap(\.costs).sorted { $0.ms > $1.ms }))
        }
        let names = record.kind == .launch ? launchNames : saveNames
        for phase in record.phases {
            guard let name = names["\(phase.from)>\(phase.to)"] else { continue }
            let costs = phase.costs.sorted { $0.ms > $1.ms }
            spans.append(ProbeLoadSpan(name: name, ms: phase.ms,
                                       attributedMs: costs.map(\.ms).reduce(0, +), costs: costs))
        }
        if let final = record.final {
            spans.append(ProbeLoadSpan(name: .waitingForPlayer,
                                       ms: max(0, final.ms - record.totalMs),
                                       attributedMs: 0, costs: []))
        }

        var byMod: [String: (ms: Double, entryMs: Double, loadMs: Double, isPack: Bool)] = [:]
        for span in spans where span.name != .waitingForPlayer {
            for cost in span.costs {
                var entry = byMod[cost.mod] ?? (0, 0, 0, false)
                entry.ms += cost.ms
                if cost.kind == .entry { entry.entryMs += cost.ms }
                if cost.kind == .load { entry.loadMs += cost.ms }
                entry.isPack = entry.isPack || cost.kind == .pack
                byMod[cost.mod] = entry
            }
        }
        let top = byMod
            .map { ProbeLoadModTotal(mod: $0.key, ms: $0.value.ms, isPack: $0.value.isPack,
                                     entryMs: $0.value.entryMs, loadMs: $0.value.loadMs) }
            .sorted { $0.ms > $1.ms }
            .prefix(5)

        return ProbeLoadBreakdown(record: record, spans: spans, top: Array(top),
                                  packSeamMissing: record.health.packSeam == "missing",
                                  assetHookMissing: record.health.assetHook == "missing",
                                  entryLoopMs: record.entryLoopMs,
                                  entryHookMissing: record.kind == .launch && record.health.entryHook == "missing",
                                  loadLoopMs: record.loadLoopMs,
                                  loadCoverage: record.loadCoveredMods.flatMap { seen in
                                      record.loadTotalMods.map { LoadCoverage(seen: seen, total: max(0, $0 - 1)) } },
                                  probeLoadsFirst: record.probeLoadsFirst)
    }
}
