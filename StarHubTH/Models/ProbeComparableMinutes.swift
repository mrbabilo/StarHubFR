import Foundation

/// Pourquoi une minute n'entre pas dans la comparaison avant/après (spec §2).
public enum ProbeExclusionReason: String, Equatable, Sendable {
    case unfocused, title, menuOpen, night, firstAfterTitle
}

public struct ProbeComparableMinute: Equatable, Sendable {
    public let minute: ProbeMinute
    /// État de la mesure des patches apparié (|ΔAt| < 30 s) ; `nil` : aucun
    /// appariement. Deux `nil` s'accordent.
    public let patchesMeasured: Bool?
}

/// Une minute écartée et la première garde qui l'a écartée.
public struct ProbeExcludedMinute: Equatable, Sendable {
    public let minute: ProbeMinute
    public let reason: ProbeExclusionReason
}

public struct ProbeComparableResult: Equatable, Sendable {
    public let kept: [ProbeComparableMinute]
    /// Première garde en échec, une seule par minute : les comptes s'additionnent.
    public let exclusions: [ProbeExclusionReason: Int]
    /// Les mêmes, minute par minute, dans l'ordre chronologique (chronologie).
    public let excluded: [ProbeExcludedMinute]

    /// La part de ces verdicts qui tombe dans `minutes` (un segment, une
    /// mesure) : mêmes gardes, recomptées. Les gardes tournent une fois par
    /// session — couper d'abord ferait passer la première minute de chaque
    /// segment pour un chargement.
    public func restricted(to minutes: [ProbeMinute]) -> ProbeComparableResult {
        let wanted = Set(minutes.map(\.at))
        let excludedHere = excluded.filter { wanted.contains($0.minute.at) }
        var counts: [ProbeExclusionReason: Int] = [:]
        for item in excludedHere { counts[item.reason, default: 0] += 1 }
        return ProbeComparableResult(kept: kept.filter { wanted.contains($0.minute.at) },
                                     exclusions: counts, excluded: excludedHere)
    }
}

public enum ProbeComparableMinutes {
    /// Les gardes de la spec (§2), dans l'ordre du tableau : la première en
    /// échec compte, une seule par minute (les comptes s'additionnent au
    /// total des minutes écartées). Une sonde < 0.4.12 (`menuShare` nil) passe
    /// la garde menu : son instantané `Menu == null` jouait ce rôle. La garde
    /// croisée des patches appartient à `ProbeComparison.patchesMismatch` :
    /// ici on attache l'état apparié.
    ///
    /// `costs` : les lignes de coûts **de la même session**
    /// (`ProbeSession.costs`), jamais le fichier entier.
    public static func filter(_ minutes: [ProbeMinute],
                              costs: [ProbeModCostMinute]) -> ProbeComparableResult {
        let ordered = minutes
            .map { ($0, ProbeDate.parse($0.at)) }
            .sorted { ($0.1 ?? .distantPast) < ($1.1 ?? .distantPast) }
        let datedCosts = costs.compactMap { cost -> (ProbeModCostMinute, Date)? in
            ProbeDate.parse(cost.at).map { (cost, $0) }
        }
        var kept: [ProbeComparableMinute] = []
        var excluded: [ProbeExcludedMinute] = []
        var exclusions: [ProbeExclusionReason: Int] = [:]
        var previousGameTime: Int?
        var previousInGame = false

        for (minute, at) in ordered {
            let reason: ProbeExclusionReason?
            if minute.isUnfocused { reason = .unfocused }
            else if minute.isAtTitle { reason = .title }
            else if let share = minute.menuShare, share >= 0.5 { reason = .menuOpen }
            else if let gameTime = minute.gameTime, let previous = previousGameTime,
                    gameTime < previous { reason = .night }
            else if !previousInGame { reason = .firstAfterTitle }
            else { reason = nil }

            // L'état suit le lieu, pas la garde : une minute en partie
            // écartée (menu, sans focus) reste en partie — seul le titre
            // referme. Sinon la garde « première en partie » ne se lèverait
            // jamais après un menu.
            if minute.isAtTitle {
                previousInGame = false
                previousGameTime = nil
            } else {
                previousInGame = true
                previousGameTime = minute.gameTime
            }

            if let reason {
                exclusions[reason, default: 0] += 1
                excluded.append(ProbeExcludedMinute(minute: minute, reason: reason))
            } else {
                kept.append(ProbeComparableMinute(
                    minute: minute, patchesMeasured: nearestCost(to: at, in: datedCosts)?.patchesMeasured))
            }
        }
        return ProbeComparableResult(kept: kept, exclusions: exclusions, excluded: excluded)
    }

    /// « Même lieu d'abord » : ≥ 5 minutes gardées de chaque côté dans des
    /// lieux présents des deux côtés → seules celles-là comptent.
    public static func restrictToSharedLocations(_ a: [ProbeComparableMinute], _ b: [ProbeComparableMinute])
        -> (a: [ProbeComparableMinute], b: [ProbeComparableMinute], restricted: Bool) {
        let common = Set(a.compactMap(\.minute.location)).intersection(b.compactMap(\.minute.location))
        let inA = a.filter { $0.minute.location.map(common.contains) == true }
        let inB = b.filter { $0.minute.location.map(common.contains) == true }
        if inA.count >= 5 && inB.count >= 5 {
            return (inA, inB, true)
        }
        return (a, b, false)
    }

    /// La ligne de coûts la plus proche, |ΔAt| < 30 s.
    private static func nearestCost(to at: Date?,
                                    in costs: [(ProbeModCostMinute, Date)]) -> ProbeModCostMinute? {
        guard let at else { return nil }
        return costs
            .filter { abs($0.1.timeIntervalSince(at)) < 30 }
            .min { abs($0.1.timeIntervalSince(at)) < abs($1.1.timeIntervalSince(at)) }?.0
    }
}
