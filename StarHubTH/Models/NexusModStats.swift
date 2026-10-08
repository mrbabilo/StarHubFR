import Foundation

/// Approbations et date de dernière mise à jour des mods du parc, **par lots
/// et sans clé** : GraphQL v2 `legacyModsByDomain` (mesuré le 2026-10-07 :
/// 80 mods au plus par réponse, ~0,2 s ; un id inconnu est absent, sans
/// erreur). Sert les tris « Approbations » et « Dernière mise à jour Nexus »
/// et le nombre affiché en liste et en grille.
enum NexusModStats {
    struct Entry: Equatable, Sendable {
        let endorsements: Int?
        let updatedAt: Date?
        /// La version d'en-tête de la page — tri sans clé de la vérification
        /// directe (2026-10-08), en retard parfois sur le fichier principal.
        var version: String? = nil
    }

    static let batchSize = 80
    static let refreshInterval: TimeInterval = 24 * 3600

    static func isDue(lastRefresh: Date?, now: Date = Date()) -> Bool {
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) >= refreshInterval
    }

    /// Identifiants valides, uniques, triés, par lots de 80.
    static func batches(_ ids: [Int]) -> [[Int]] {
        let unique = Array(Set(ids.filter { $0 > 0 })).sorted()
        return stride(from: 0, to: unique.count, by: batchSize).map {
            Array(unique[$0..<min($0 + batchSize, unique.count)])
        }
    }

    static func body(ids: [Int]) -> Data? {
        let query = """
        query ModStats($ids: [CompositeDomainWithIdInput!]!, $c: Int) {
          legacyModsByDomain(ids: $ids, count: $c) { nodes { modId endorsements updatedAt version } }
        }
        """
        let variables: [String: Any] = [
            "c": batchSize,
            "ids": ids.map { ["gameDomain": NexusRequestBuilder.gameDomain, "modId": $0] },
        ]
        return try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
    }

    /// `nil` si la réponse porte des erreurs ou n'est pas lisible : un lot
    /// en échec ne vaut pas « aucun mod ».
    static func decode(_ data: Data) -> [Int: Entry]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (root["errors"] as? [Any])?.isEmpty ?? true,
              let nodes = ((root["data"] as? [String: Any])?["legacyModsByDomain"] as? [String: Any])?["nodes"]
                as? [[String: Any]] else { return nil }
        var stats: [Int: Entry] = [:]
        for node in nodes {
            guard let id = (node["modId"] as? Int) ?? (node["modId"] as? String).flatMap(Int.init) else { continue }
            stats[id] = Entry(endorsements: node["endorsements"] as? Int,
                              updatedAt: (node["updatedAt"] as? String).flatMap(NexusModSearch.parseDate),
                              version: node["version"] as? String)
        }
        return stats
    }

    /// Met à jour nombre et date ; le reste de chaque entrée (résumé, image,
    /// version) est gardé ; un mod sans entrée en reçoit une minimale.
    static func merge(_ stats: [Int: Entry],
                      into extras: [String: NexusUpdateChecker.NexusModExtra]) -> [String: NexusUpdateChecker.NexusModExtra] {
        var merged = extras
        for (id, entry) in stats {
            var extra = merged[String(id)] ?? .init(summary: "", pictureUrl: "")
            if let count = entry.endorsements { extra.endorsements = count }
            if let date = entry.updatedAt { extra.uploadedTime = date }
            merged[String(id)] = extra
        }
        return merged
    }
}
