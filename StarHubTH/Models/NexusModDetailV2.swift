import Foundation

/// A3-T7 — la description et l'historique de la fiche par l'API v2
/// GraphQL, qui les rend **sans clé**. Repli de la voie v1 (`mods/{id}.json`,
/// `changelogs.json`) quand la clé manque ou que le quota est épuisé.
///
/// Mesuré le 2026-09-25 contre les 31 fiches du cache v1 : descriptions
/// identiques (même BBCode), et avec la règle de fusion ci-dessous **609
/// versions sur 609** identiques. Écart connu : la v2 range l'historique par
/// **fichier**, la v1 par version — une version dont le fichier a été
/// supprimé n'a pas d'entrée ici (6 versions sur 615, ~1 %).
enum NexusModDetailV2 {

    /// Une seule requête : la description par le même `mods(filter:)` que la
    /// fiche de Découvrir (`NexusModSearch.detailBody`), plus `modFiles`.
    static func body(modId: Int, gameId: Int) -> Data? {
        let query = """
        query ModDetailRaw($game: String!, $id: String!, $modId: ID!, $gameId: ID!) {
          mods(filter: { gameId: { value: $game, op: EQUALS },
                         modId: { value: $id, op: EQUALS } }, count: 1) {
            nodes { description }
          }
          modFiles(modId: $modId, gameId: $gameId) { version date changelogText }
        }
        """
        let variables: [String: Any] = ["game": String(gameId), "id": String(modId),
                                        "modId": String(modId), "gameId": String(gameId)]
        do {
            return try JSONSerialization.data(withJSONObject: ["query": query,
                                                               "variables": variables])
        } catch {
            return nil
        }
    }

    /// Lit la réponse en `ModDetailRaw`. `errors` l'emporte ; une description
    /// absente ou vide est un échec (même règle que la v1 : le repli local de
    /// l'appelant reste en place) ; un historique vide est acceptable.
    static func decode(_ data: Data) -> Result<ModDetailRaw, NexusModSearch.Failure> {
        let parsed: Any
        do { parsed = try JSONSerialization.jsonObject(with: data) } catch { return .failure(.malformed) }
        guard let root = parsed as? [String: Any] else { return .failure(.malformed) }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            let message = errors.compactMap { $0["message"] as? String }.joined(separator: " · ")
            return .failure(.service(message.isEmpty ? "unknown" : message))
        }
        let payload = root["data"] as? [String: Any]
        let nodes = (payload?["mods"] as? [String: Any])?["nodes"] as? [[String: Any]]
        guard let description = nodes?.first?["description"] as? String, !description.isEmpty
        else { return .failure(.malformed) }
        let files = (payload?["modFiles"] as? [[String: Any]]) ?? []
        let changelog = NexusUpdateChecker.formatChangelogs(mergeChangelogs(files))
        return .success(ModDetailRaw(description: description, changelog: changelog))
    }

    /// `modFiles` → `{version: [lignes]}`, le format de la v1. Plusieurs
    /// fichiers portent souvent la même version (principal + optionnels,
    /// doublons archivés) avec le **même** journal : il compte une fois. Un
    /// journal **différent** pour la même version ajoute ses lignes pas
    /// encore vues. ⚠️ Jamais de dédoublonnage ligne à ligne à l'intérieur
    /// d'un fichier : un journal répète légitimement « . » ou « * » comme
    /// séparateur (SVE 1.14.14), et la v1 les garde.
    static func mergeChangelogs(_ files: [[String: Any]]) -> [String: [String]] {
        let ordered = files.sorted {
            (($0["date"] as? Int) ?? 0) < (($1["date"] as? Int) ?? 0)
        }
        var merged: [String: [String]] = [:]
        for file in ordered {
            guard let version = file["version"] as? String, !version.isEmpty,
                  let lines = file["changelogText"] as? [String], !lines.isEmpty
            else { continue }
            guard let existing = merged[version] else {
                merged[version] = lines
                continue
            }
            if lines != existing {
                merged[version] = existing + lines.filter { !existing.contains($0) }
            }
        }
        return merged
    }
}
