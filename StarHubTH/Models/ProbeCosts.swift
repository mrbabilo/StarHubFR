import Foundation

/// L'écart de coût propre d'un mod entre avant (A) et après (B).
public struct ProbeCostDelta: Equatable, Sendable {
    public enum Presence: Equatable, Sendable { case both, added, removed }
    public let modId: String
    public let msPerSecondA: Double?
    public let msPerSecondB: Double?
    public let presence: Presence

    /// B − A ; un mod absent d'un côté porte son coût entier.
    public var delta: Double {
        switch presence {
        case .both: (msPerSecondB ?? 0) - (msPerSecondA ?? 0)
        case .added: msPerSecondB ?? 0
        case .removed: -(msPerSecondA ?? 0)
        }
    }
}

public enum ProbeCosts {
    /// ms de temps propre par seconde de jeu, par mod, sur les minutes
    /// gardées : `somme(SelfMs) / somme(WallSeconds)`, robuste aux minutes
    /// inégales. Seules les minutes appariées à une ligne de coûts (|ΔAt|
    /// < 30 s) comptent ; un mod absent d'une ligne compte 0 — il n'a pas
    /// tourné cette minute-là. `costs` : les lignes de la même session.
    public static func perMod(_ side: [ProbeComparableMinute],
                              costs: [ProbeModCostMinute]) -> [String: Double] {
        let dated = costs.compactMap { line in ProbeDate.parse(line.at).map { (line, $0) } }
        var selfMs: [String: Double] = [:]
        var seconds = 0.0
        for item in side {
            guard let at = ProbeDate.parse(item.minute.at),
                  let line = dated
                      .filter({ abs($0.1.timeIntervalSince(at)) < 30 })
                      .min(by: { abs($0.1.timeIntervalSince(at)) < abs($1.1.timeIntervalSince(at)) })?.0
            else { continue }
            seconds += line.wallSeconds
            for mod in line.mods {
                selfMs[mod.mod, default: 0] += mod.selfMs
            }
        }
        guard seconds > 0 else { return [:] }
        return selfMs.mapValues { $0 / seconds }
    }

    /// Triés par impact (|delta| décroissant), départagés par `modId`.
    public static func delta(_ a: [String: Double], _ b: [String: Double]) -> [ProbeCostDelta] {
        var deltas: [ProbeCostDelta] = []
        for (id, costA) in a {
            deltas.append(ProbeCostDelta(modId: id, msPerSecondA: costA, msPerSecondB: b[id],
                                         presence: b[id] == nil ? .removed : .both))
        }
        for (id, costB) in b where a[id] == nil {
            deltas.append(ProbeCostDelta(modId: id, msPerSecondA: nil, msPerSecondB: costB, presence: .added))
        }
        return deltas.sorted {
            abs($0.delta) != abs($1.delta) ? abs($0.delta) > abs($1.delta) : $0.modId < $1.modId
        }
    }
}
