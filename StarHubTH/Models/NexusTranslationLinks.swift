import Foundation

/// C5-T1 — les traductions **liées** à un mod sur Nexus : les fiches qui le
/// déclarent comme prérequis (`modRequirements.modsRequiringThisMod`).
///
/// Mesuré sur le parc le 2026-09-24 (SOURCES §2.4) : sur 87 identifiants de
/// mods traduisibles sans français, ce lien trouve 10 traductions françaises,
/// **toutes justes** ; la recherche par nom + tag `French` en rend 11 dont 4
/// fausses, et ses 7 justes sont déjà dans les 10. Le lien ne porte pas de
/// langue : on relit chaque fiche liée (tags, titre) par lots d'identifiants.
///
/// La section « Translations » de la page web (langue → fiche) n'est pas
/// exposée par le schéma : ce lien est ce qui s'en approche le plus.
extension NexusModSearch {

    /// Une tranche de la liste des fiches qui déclarent un mod comme prérequis.
    public struct RequiringPage: Equatable, Sendable {
        public let modIds: [Int]
        public let totalCount: Int
        public init(modIds: [Int], totalCount: Int) {
            self.modIds = modIds; self.totalCount = totalCount
        }
    }

    /// Taille d'une tranche : 80 est ce que la page de SVE (756 requérants) a
    /// servi sans broncher ; c'est aussi la taille d'un lot de relecture.
    public static let requiringPageSize = 80

    /// Au-delà, on s'arrête : SVE a 756 requérants, et ses traductions ne sont
    /// pas plus tardives que les autres dans la liste. Dix tranches couvrent le
    /// plus gros mod du parc sans laisser un seul mod coûter cinquante requêtes.
    public static let requiringScanLimit = 800

    public static func requiringBody(modId: Int, gameId: Int, offset: Int = 0,
                                     count: Int = requiringPageSize) -> Data? {
        let query = """
        query Requiring($game: String!, $id: String!, $count: Int!, $offset: Int!) {
          mods(filter: { gameId: { value: $game, op: EQUALS },
                         modId: { value: $id, op: EQUALS } }, count: 1) {
            nodes { modRequirements {
              modsRequiringThisMod(count: $count, offset: $offset) {
                totalCount nodes { modId }
              } } }
          }
        }
        """
        let variables: [String: Any] = ["game": String(gameId), "id": String(modId),
                                        "count": count, "offset": offset]
        return try? JSONSerialization.data(withJSONObject: ["query": query,
                                                            "variables": variables])
    }

    /// Même règles que `decode` : `errors` l'emporte sur un 200. Un mod que
    /// Nexus ne connaît pas (fiche retirée) rend une page vide, pas une panne.
    public static func decodeRequiring(_ data: Data) -> Result<RequiringPage, Failure> {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(.malformed)
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            let message = errors.compactMap { $0["message"] as? String }.joined(separator: " · ")
            return .failure(.service(message.isEmpty ? "unknown" : message))
        }
        guard let payload = root["data"] as? [String: Any],
              let mods = payload["mods"] as? [String: Any],
              let nodes = mods["nodes"] as? [[String: Any]]
        else { return .failure(.malformed) }
        guard let first = nodes.first else { return .success(RequiringPage(modIds: [], totalCount: 0)) }
        guard let requirements = first["modRequirements"] as? [String: Any],
              let requiring = requirements["modsRequiringThisMod"] as? [String: Any],
              let items = requiring["nodes"] as? [[String: Any]]
        else { return .failure(.malformed) }
        // `modId` arrive en chaîne ici (type `ID`) : les deux formes sont lues.
        let ids = items.compactMap { item -> Int? in
            if let value = item["modId"] as? Int { return value }
            return (item["modId"] as? String).flatMap { Int($0) }
        }
        return .success(RequiringPage(modIds: ids,
                                      totalCount: (requiring["totalCount"] as? Int) ?? ids.count))
    }

    /// Relire des fiches par identifiants, en un appel. Le filtre `modId` exige
    /// `gameId` **dans la même clause** : un `OR` de clauses complètes, mesuré
    /// à 80 identifiants en 0,27 s. Les fiches cachées ou retirées sont omises
    /// par le serveur (42 rendues sur 80 pour la première tranche de SVE).
    /// Mêmes champs que la recherche : la réponse se lit avec `decode`.
    public static func modsByIdsBody(_ modIds: [Int], gameId: Int) -> Data? {
        guard !modIds.isEmpty else { return nil }
        let query = """
        query ModsByIds($filters: [ModsFilter!], $count: Int!) {
          mods(filter: { op: OR, filter: $filters }, count: $count) {
            totalCount
            nodes { modId name version updatedAt adultContent status thumbnailUrl
                    modCategory { categoryId name } uploader { name } tags { name } }
          }
        }
        """
        let filters: [[String: Any]] = modIds.map {
            ["gameId": [["value": String(gameId), "op": "EQUALS"]],
             "modId": [["value": String($0), "op": "EQUALS"]]]
        }
        return try? JSONSerialization.data(withJSONObject: [
            "query": query, "variables": ["filters": filters, "count": modIds.count]])
    }

    /// Parmi les fiches liées à un mod, ses traductions françaises : le tag
    /// `French` **ou** un titre qui l'annonce (3 traductions sur 80 n'ont pas
    /// le tag). Le lien suffit à dire « ce mod-là » ; il reste à dire « en
    /// français ». La plus récente en tête.
    public static func linkedFrenchTranslations(_ hits: [Hit], hostModId: Int) -> [Hit] {
        hits.filter { hit in
            hit.modId != hostModId
                && (hit.tags.contains { $0.caseInsensitiveCompare(frenchTag) == .orderedSame }
                    || announcesFrenchTranslation(hit.name))
        }
        .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }
}
