import Foundation
import Darwin

/// Comparaison avant/après des chargements (D5-B, spec §5) : deux côtés de
/// même état du parc, verdict sur les médianes, écarts par mod. Pure, testée.
public enum ProbeLoadExclusion: Hashable, Sendable {
    case incomplete
    case coldDisk
    case olderProbe
    case otherSave
    case saveSize
    case reloadDiffers
    case patchesDiffer
    case probePosition
    case noInventory
}

public enum ProbeLoadVerdict: Equatable, Sendable {
    case faster(seconds: Double, percent: Double)
    case slower(seconds: Double, percent: Double)
    case noDifference
    /// Écart entre le bruit observé et le seuil, ou un côté à une seule session.
    case grayZone(beforeCount: Int, afterCount: Int)

    /// Verdict tranché : l'écran suffixe « indicatif » quand faux.
    public var isDecided: Bool {
        switch self {
        case .faster, .slower: return true
        case .noDifference, .grayZone: return false
        }
    }

    var isFaster: Bool {
        if case .faster = self { return true }
        return false
    }
}

public struct ProbeLoadModDelta: Equatable, Sendable, Identifiable {
    public var id: String { mod }
    public let mod: String
    public let deltaMs: Double

    public init(mod: String, deltaMs: Double) {
        self.mod = mod
        self.deltaMs = deltaMs
    }
}

public struct ProbeLoadComparisonResult: Equatable, Sendable {
    public let kind: ProbeLoadRecord.Kind
    /// Côté « avant » : état le plus récent différent de la référence.
    public let before: [ProbeLoadRecord]
    /// Côté « après » : comparables du même état que la référence.
    public let after: [ProbeLoadRecord]
    public let diff: ProbeInventoryDiff
    public let verdict: ProbeLoadVerdict
    public let modDeltas: [ProbeLoadModDelta]
    public let exclusions: [ProbeLoadExclusion: Int]
}

public enum ProbeLoadComparison {
    /// Option 4 (2026-09-30) : pas de constante de bruit. La tâche 0 avait
    /// mesuré 2,2 % **sans** la sonde ; trois sessions 0.6.2 sur le parc de
    /// 286 mods ont donné 8,9 % au lancement et 5,3 % au chargement, surtout
    /// par la première session de la série. Le bruit dépend du parc, du disque
    /// et du jour : chaque comparaison le mesure sur ses propres sessions —
    /// le plus grand écart (max − min) / min d'un côté ou de l'autre. Nil
    /// quand aucun côté n'a deux sessions.
    public static func observedNoisePercent(before: [Double], after: [Double]) -> Double? {
        let spreads = [before, after].compactMap { side -> Double? in
            guard side.count >= 2, let low = side.min(), let high = side.max(), low > 0 else { return nil }
            return (high - low) / low * 100
        }
        return spreads.max()
    }

    /// max(3 %, 2 × bruit). Plancher abaissé de 5 à 3 % le 2026-10-01 : deux
    /// A/B d'un mod isolé (−3 et −4 %) restaient gris. 3 % reste au-dessus des
    /// deux faux écarts mesurés sans rien changer — 2,2 % (A/A des chargements
    /// sans sonde) et 1,97 % (A/A de D5-A, quartiles disjoints) — et ne
    /// descend pas plus bas pour cette raison. Une série dispersée est tenue
    /// par 2 × bruit, pas par le plancher.
    public static func thresholdPercent(noise: Double) -> Double { max(3, 2 * noise) }

    /// Froid (tâche 0) : la première session après le démarrage du Mac a
    /// mesuré +98 % au lancement et +17 % au chargement — largement au-dessus
    /// du seuil, la détection vaut la peine (`matters = true`). La date de
    /// naissance du point de montage de `BABILOGAMES` est figée (oct. 2024,
    /// vérifié au remontage) : seul `kern.boottime` fonde la règle. La session
    /// d'éjection (aa-froid.txt) a confirmé : éjecter-remonter ne refroidit
    /// rien (47 s / 58 s, comme les chaudes).
    static let coldMatters = true

    /// Vrai pour le premier lancement, parmi tous les enregistrements, dont
    /// `at` est postérieur à `coldBefore` (démarrage du Mac) : le cache disque
    /// de l'OS y est froid. `coldBefore == nil` : jamais froid.
    public static func isCold(_ record: ProbeLoadRecord, among records: [ProbeLoadRecord],
                              coldBefore: Date?) -> Bool {
        guard coldMatters, let coldBefore, record.kind == .launch else { return false }
        let afterBoot = records.filter { $0.kind == .launch && ($0.at ?? .distantFuture) >= coldBefore }
        guard let first = afterBoot.min(by: { ($0.at ?? .distantFuture) < ($1.at ?? .distantFuture) }) else { return false }
        return first.id == record.id
    }

    /// Les motifs d'exclusion, candidat par candidat, contre la référence.
    /// Ordre du premier motif qui s'applique : incomplete, coldDisk, olderProbe,
    /// otherSave, saveSize, reloadDiffers, patchesDiffer, probePosition, noInventory.
    public static func exclusions(_ records: [ProbeLoadRecord], kind: ProbeLoadRecord.Kind,
                                  launches: [ProbeInventoryLaunch], changes: [ProbeInventoryChange],
                                  coldBefore: Date?) -> [ProbeLoadExclusion: Int] {
        guard let reference = records.filter({ $0.kind == kind && $0.complete })
            .max(by: { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) })
        else { return [:] }
        var counts: [ProbeLoadExclusion: Int] = [:]
        for record in records where record.kind == kind {
            guard let reason = reason(record: record, reference: reference, kind: kind,
                                      records: records, launches: launches, changes: changes,
                                      coldBefore: coldBefore) else { continue }
            counts[reason, default: 0] += 1
        }
        return counts
    }

    /// Compare deux états du parc : dernier enregistrement complet du `kind`
    /// comme référence ; « après » = comparables du même état ; « avant » =
    /// comparables de l'état complet le plus récent différent. Verdict sur
    /// les médianes des totaux.
    public static func compare(_ records: [ProbeLoadRecord], kind: ProbeLoadRecord.Kind,
                               launches: [ProbeInventoryLaunch], changes: [ProbeInventoryChange],
                               coldBefore: Date?) -> ProbeLoadComparisonResult? {
        guard let reference = records.filter({ $0.kind == kind && $0.complete })
            .max(by: { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) })
        else { return nil }
        var exclusions: [ProbeLoadExclusion: Int] = [:]
        var comparable: [ProbeLoadRecord] = []
        for record in records where record.kind == kind {
            if let reason = reason(record: record, reference: reference, kind: kind,
                                   records: records, launches: launches, changes: changes,
                                   coldBefore: coldBefore) {
                exclusions[reason, default: 0] += 1
            } else {
                comparable.append(record)
            }
        }
        guard let referenceState = state(of: reference, launches: launches, changes: changes) else { return nil }
        let after = comparable.filter { record in
            guard let recordState = state(of: record, launches: launches, changes: changes) else { return false }
            return ProbeInventoryDiffRule.between(referenceState, recordState).changes.isEmpty
        }
        // État le plus récent différent de la référence, parmi les comparables.
        let anchor = comparable
            .filter { record in
                guard let recordState = state(of: record, launches: launches, changes: changes) else { return false }
                return !ProbeInventoryDiffRule.between(referenceState, recordState).changes.isEmpty
            }
            .max(by: { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) })
        guard let anchor else { return nil }
        guard let anchorState = state(of: anchor, launches: launches, changes: changes) else { return nil }
        let before = comparable.filter { record in
            guard let recordState = state(of: record, launches: launches, changes: changes) else { return false }
            return ProbeInventoryDiffRule.between(anchorState, recordState).changes.isEmpty
        }
        guard !before.isEmpty, !after.isEmpty, anchor.id != reference.id else { return nil }

        let verdict = verdict(before: before.map(\.totalMs), after: after.map(\.totalMs))
        return ProbeLoadComparisonResult(
            kind: kind, before: before.sorted { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) },
            after: after.sorted { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) },
            diff: ProbeInventoryDiffRule.between(anchorState, referenceState),
            verdict: verdict, modDeltas: deltas(before: before, after: after),
            exclusions: exclusions)
    }

    /// Verdict sur les médianes, en millisecondes. Tranché seulement avec au
    /// moins deux sessions de chaque côté (sans quoi le bruit est inconnu) et
    /// au-delà du seuil ; « pas de différence » sous le bruit observé ; zone
    /// grise sinon.
    public static func verdict(before: [Double], after: [Double]) -> ProbeLoadVerdict {
        guard let beforeMs = median(before), let afterMs = median(after), beforeMs > 0 else {
            return .noDifference
        }
        let gray = ProbeLoadVerdict.grayZone(beforeCount: before.count, afterCount: after.count)
        guard before.count >= 2, after.count >= 2,
              let noise = observedNoisePercent(before: before, after: after) else { return gray }
        let percent = (afterMs - beforeMs) / beforeMs * 100
        if abs(percent) > thresholdPercent(noise: noise) {
            let seconds = abs(beforeMs - afterMs) / 1000
            return percent < 0 ? .faster(seconds: seconds, percent: abs(percent))
                               : .slower(seconds: seconds, percent: percent)
        }
        if abs(percent) <= noise { return .noDifference }
        return gray
    }

    // MARK: — Privé

    /// Le premier motif qui s'applique, ou nil si le candidat est comparable.
    private static func reason(record: ProbeLoadRecord, reference: ProbeLoadRecord, kind: ProbeLoadRecord.Kind,
                               records: [ProbeLoadRecord], launches: [ProbeInventoryLaunch],
                               changes: [ProbeInventoryChange], coldBefore: Date?) -> ProbeLoadExclusion? {
        if !record.complete { return .incomplete }
        if isCold(record, among: records, coldBefore: coldBefore) { return .coldDisk }
        if record.probeVersion != reference.probeVersion { return .olderProbe }
        if kind == .save {
            if record.saveName?.caseInsensitiveCompare(reference.saveName ?? "") != .orderedSame {
                return .otherSave
            }
            // La sauvegarde grossit avec le jeu (14,4 → 33,9 Mo en 18 jours) :
            // au-delà de 1 %, deux mesures ne décrivent pas le même fichier.
            if let bytes = record.saveBytes, let refBytes = reference.saveBytes {
                if abs(Double(bytes - refBytes)) / Double(refBytes) > 0.01 { return .saveSize }
            } else {
                return .saveSize
            }
        }
        if record.reload != reference.reload { return .reloadDiffers }
        if record.patchesMeasured != reference.patchesMeasured { return .patchesDiffer }
        // Sonde en tête (ModsToLoadEarly) : L1 passe du milieu au début de la
        // boucle de démarrage, les phases changent de sens.
        if record.probeLoadsFirst != reference.probeLoadsFirst { return .probePosition }
        if state(of: record, launches: launches, changes: changes) == nil { return .noInventory }
        return nil
    }

    private static func state(of record: ProbeLoadRecord, launches: [ProbeInventoryLaunch],
                              changes: [ProbeInventoryChange]) -> ProbeInventoryLaunch? {
        // Un `configChanged` pendant la session compte s'il précède
        // l'enregistrement (`upTo`) : c'est l'état au clic sur la sauvegarde.
        guard let upTo = record.at ?? ProbeDate.parse(record.atText),
              let launch = launches.first(where: { $0.session == record.session }) else { return nil }
        return ProbeSegments.resolvedInventory(launch: launch, changes: changes, upTo: upTo)
    }

    /// Écart par mod : médiane « après » moins médiane « avant » de la somme
    /// de ses coûts sur les spans du total ; les cinq plus gros écarts.
    private static func deltas(before: [ProbeLoadRecord], after: [ProbeLoadRecord]) -> [ProbeLoadModDelta] {
        func sums(_ records: [ProbeLoadRecord]) -> [String: [Double]] {
            var out: [String: [Double]] = [:]
            for record in records {
                var byMod: [String: Double] = [:]
                for phase in record.phases {
                    for cost in phase.costs {
                        byMod[cost.mod, default: 0] += cost.ms
                    }
                }
                for (mod, ms) in byMod {
                    out[mod, default: []].append(ms)
                }
            }
            return out
        }
        let beforeSums = sums(before), afterSums = sums(after)
        return Set(beforeSums.keys).union(afterSums.keys)
            .map { mod in ProbeLoadModDelta(mod: mod,
                                            deltaMs: (median(afterSums[mod] ?? []) ?? 0) - (median(beforeSums[mod] ?? []) ?? 0)) }
            .sorted { abs($0.deltaMs) > abs($1.deltaMs) }
            .prefix(5)
            .map { $0 }
    }

    /// Médiane : la valeur centrale, ou la moyenne des deux centrales.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

/// Où commence le cache disque froid (spec §5, tâche 0) : le démarrage du
/// Mac, ou le montage du volume du jeu s'il est plus récent. Lecture système,
/// pas de test unitaire.
public enum ProbeColdDisk {
    /// Tâche 0 (2026-09-30) : la première session après le démarrage a mesuré
    /// +98 % au lancement, +17 % au chargement — largement au-dessus du seuil
    /// de 3 % : la détection vaut la peine.
    static let matters = true

    /// L'instant avant lequel un lancement est « froid ». La date de naissance
    /// du point de montage est figée (vérifié au remontage du 2026-09-30) :
    /// seul `kern.boottime` entre ici.
    public static func cutoff(gameDir: String?) -> Date? {
        guard matters else { return nil }
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
    }
}
