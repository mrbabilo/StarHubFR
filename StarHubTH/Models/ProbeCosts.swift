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

/// D5-C — ce qu'un mod a coûté sur les minutes gardées d'un segment.
public struct ProbeModStats: Equatable, Sendable {
    /// Temps propre (patches compris si mesurés) par seconde de jeu.
    public let msPerSecond: Double
    /// Le plus long appel vu sur une minute appariée.
    public let maxMs: Double
    /// Allocations (pression GC), pas mémoire retenue.
    public let allocMBPerMinute: Double
}

/// D5-C — les agrégats d'un segment : par mod, et ce qu'il faut pour
/// convertir (FPS moyen, travail de trame) et qualifier (patches mesurés).
public struct ProbeSegmentCosts: Equatable, Sendable {
    public let mods: [String: ProbeModStats]
    public let seconds: Double
    public let frames: Int
    public let frameWorkMs: Double
    /// Lignes de coûts appariées, et celles dont les patches étaient mesurés.
    public let lines: Int
    public let patchesMeasuredLines: Int

    public var fps: Double { seconds > 0 ? Double(frames) / seconds : 0 }
}

public enum ProbeCosts {
    /// ms de temps propre par seconde de jeu, par mod, sur les minutes
    /// gardées : `somme(SelfMs) / somme(WallSeconds)`, robuste aux minutes
    /// inégales. Seules les minutes appariées à une ligne de coûts (|ΔAt|
    /// < 30 s) comptent ; un mod absent d'une ligne compte 0 — il n'a pas
    /// tourné cette minute-là. `costs` : les lignes de la même session.
    public static func perMod(_ side: [ProbeComparableMinute],
                              costs: [ProbeModCostMinute]) -> [String: Double] {
        segmentCosts(side, costs: costs).mods.mapValues(\.msPerSecond)
    }

    /// Même appariement que `perMod` (une ligne de coûts par minute gardée,
    /// |ΔAt| < 30 s, une seule fois) ; un mod absent d'une ligne compte 0.
    public static func segmentCosts(_ side: [ProbeComparableMinute],
                                    costs: [ProbeModCostMinute]) -> ProbeSegmentCosts {
        let dated = costs.compactMap { line in ProbeDate.parse(line.at).map { (line, $0) } }
        var selfMs: [String: Double] = [:], maxMs: [String: Double] = [:], allocKB: [String: Double] = [:]
        var seconds = 0.0, frames = 0, frameWorkMs = 0.0, lines = 0, patched = 0
        // Une ligne ne s'apparie qu'une fois : deux minutes proches la
        // compteraient deux fois.
        var used = Set<Int>()
        for item in side {
            guard let at = ProbeDate.parse(item.minute.at),
                  let index = dated.indices
                      .filter({ !used.contains($0) && abs(dated[$0].1.timeIntervalSince(at)) < 30 })
                      .min(by: { abs(dated[$0].1.timeIntervalSince(at)) < abs(dated[$1].1.timeIntervalSince(at)) })
            else { continue }
            used.insert(index)
            let line = dated[index].0
            seconds += line.wallSeconds
            frames += line.frames
            frameWorkMs += line.frameWorkMs ?? 0
            lines += 1
            if line.patchesMeasured == true { patched += 1 }
            for mod in line.mods {
                selfMs[mod.mod, default: 0] += mod.selfMs
                maxMs[mod.mod] = max(maxMs[mod.mod] ?? 0, mod.maxMs)
                allocKB[mod.mod, default: 0] += mod.allocKB
            }
        }
        guard seconds > 0 else {
            return ProbeSegmentCosts(mods: [:], seconds: 0, frames: 0, frameWorkMs: 0, lines: 0, patchesMeasuredLines: 0)
        }
        var mods: [String: ProbeModStats] = [:]
        for (id, ms) in selfMs {
            mods[id] = ProbeModStats(msPerSecond: ms / seconds, maxMs: maxMs[id] ?? 0,
                                     allocMBPerMinute: (allocKB[id] ?? 0) / 1024 / seconds * 60)
        }
        return ProbeSegmentCosts(mods: mods, seconds: seconds, frames: frames, frameWorkMs: frameWorkMs,
                                 lines: lines, patchesMeasuredLines: patched)
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
