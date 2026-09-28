import Foundation

/// Un morceau de session à parc constant : entre deux changements de
/// réglages (`configChanged`), l'inventaire ne bouge pas.
public struct ProbeSegment: Equatable, Sendable {
    public let session: String
    /// Début de session, ou `ChangedAt` de la coupure précédente.
    public let start: Date?
    /// `ChangedAt` de la coupure qui le termine ; la fin de la dernière
    /// minute pour le dernier segment.
    public let end: Date?
    /// Inventaire résolu (launch + changements appliqués). `nil` : session
    /// sans inventaire (sonde < 0.4.12) — affichable, jamais source de diff.
    public let inventory: [String: ProbeInventoryEntry]?
    /// Peut être vide : le premier segment d'une session inventoriée est
    /// toujours rendu, même quand toutes les minutes suivent la coupure
    /// (horloge disque décalée).
    public let minutes: [ProbeMinute]
}

public struct ProbeSegmentsResult: Equatable, Sendable {
    public let segments: [ProbeSegment]
    /// Minutes dont la fenêtre contient une coupure : écartées.
    public let mixedMinutes: [ProbeMinute]
}

public enum ProbeSegments {
    /// Une minute couvre `(fin de la précédente, sienne]` : la coupure qui
    /// tombe dans cette fenêtre la rend mixte. Chaque autre minute se range
    /// dans le segment où elle se termine (`k` = nombre de coupures passées).
    /// Une coupure hors des bornes (horloge disque décalée) ne perd aucune
    /// minute : elles tombent toutes d'un même côté.
    public static func split(_ session: ProbeSession,
                             launches: [ProbeInventoryLaunch],
                             changes: [ProbeInventoryChange]) -> ProbeSegmentsResult {
        let launch = launches.first { $0.session == session.id }
        let sessionChanges = changes.filter { $0.session == session.id }
        let cuts = sessionChanges.compactMap { $0.changedAt ?? $0.at }.sorted()
        guard launch != nil || !cuts.isEmpty else {
            // Sans inventaire ni coupure : un segment « inconnu », jamais
            // source de différences.
            return ProbeSegmentsResult(
                segments: [ProbeSegment(session: session.id, start: session.startedAt,
                                        end: lastAt(session), inventory: nil,
                                        minutes: session.minutes)],
                mixedMinutes: [])
        }

        let sessionStart = session.startedAt
        let ordered = session.minutes
            .compactMap { minute -> (minute: ProbeMinute, end: Date)? in
                ProbeDate.parse(minute.at).map { (minute, $0) }
            }
            .sorted { $0.end < $1.end }

        // Rangement : k = nombre de coupures ≤ fin de la minute ; mixte quand
        // la dernière coupure passée est entrée dans la fenêtre courante.
        var buckets: [[ProbeMinute]] = .init(repeating: [], count: cuts.count + 1)
        var mixed: [ProbeMinute] = []
        var previousEnd = sessionStart
        for entry in ordered {
            let k = (cuts.firstIndex { $0 > entry.end }) ?? cuts.count
            if k > 0, let windowStart = previousEnd, cuts[k - 1] > windowStart {
                mixed.append(entry.minute)
            } else {
                buckets[k].append(entry.minute)
            }
            previousEnd = entry.end
        }

        // Inventaire résolu, coupure après coupure.
        var inventory = launch.map { $0.byModId }
        var segments: [ProbeSegment] = []
        for k in 0...cuts.count {
            if k > 0 {
                inventory = applyCut(inventory, changes: sessionChanges, at: cuts[k - 1])
            }
            guard !buckets[k].isEmpty || (k == 0 && launch != nil) else { continue }
            let start = k == 0 ? sessionStart : cuts[k - 1]
            let end = k == cuts.count ? lastAt(session) : cuts[k]
            segments.append(ProbeSegment(session: session.id, start: start, end: end,
                                         inventory: inventory, minutes: buckets[k]))
        }
        return ProbeSegmentsResult(segments: segments, mixedMinutes: mixed)
    }

    // MARK: — Privé

    /// Applique sur l'inventaire résolu les changements dont la coupure est
    /// `at` : la nouvelle empreinte remplace l'ancienne (le mod était chargé),
    /// un `sha` nul met `configSha` à `nil` (config supprimé).
    private static func applyCut(_ inventory: [String: ProbeInventoryEntry]?,
                                 changes: [ProbeInventoryChange],
                                 at: Date) -> [String: ProbeInventoryEntry]? {
        guard var inventory else { return nil }
        for change in changes where (change.changedAt ?? change.at) == at {
            for (modId, sha) in change.configs {
                guard let previous = inventory[modId] else { continue }
                inventory[modId] = ProbeInventoryEntry(modId: modId, version: previous.version,
                                                       configSha: sha)
            }
        }
        return inventory
    }

    private static func lastAt(_ session: ProbeSession) -> Date? {
        session.minutes.compactMap { ProbeDate.parse($0.at) }.max()
    }
}
