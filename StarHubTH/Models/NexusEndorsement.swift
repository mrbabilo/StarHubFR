import Foundation

/// A3-T8 — approuver (« endorse ») un mod sur Nexus, ou s'en abstenir.
///
/// Chemins : spécification officielle de l'API v1. Corps et réponses : le
/// client officiel de Nexus (`node-nexus-api`, celui de Vortex) — POST JSON
/// `{"Version": …}` (une version qui existe sur Nexus), réponse
/// `{message, status}`, erreur dans `message` ou `error` ;
/// `TOO_SOON_AFTER_DOWNLOAD` (15 min) et `NOT_DOWNLOADED_MOD` y sont
/// traduits, `IS_OWN_MOD` vient de Vortex et Stardrop. Toute autre réponse
/// remonte en `unknown` avec son code et son texte, jamais en silence.
public enum NexusEndorsement {
    public enum Status: Equatable, Sendable { case endorsed, abstained, undecided }

    public enum Outcome: Equatable, Sendable {
        case endorsed, abstained
        case isOwnMod, tooSoonAfterDownload, notDownloaded
        case unknown(httpStatus: Int, message: String?)
    }

    public static let listPath = "/user/endorsements.json"

    public static func path(modId: Int, endorse: Bool) -> String {
        "/games/\(NexusRequestBuilder.gameDomain)/mods/\(modId)/\(endorse ? "endorse" : "abstain").json"
    }

    /// `{"Version": "<version installée>"}` ; `{}` sans version connue.
    public static func body(version: String) -> Data {
        let object: [String: String] = version.isEmpty ? [:] : ["Version": version]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }

    /// L'état de chaque mod Stardew du compte, ou `nil` si le corps n'est pas
    /// la liste attendue.
    public static func statuses(from data: Data) -> [Int: Status]? {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var map: [Int: Status] = [:]
        for row in rows {
            guard (row["domain_name"] as? String)?.caseInsensitiveCompare(NexusRequestBuilder.gameDomain) == .orderedSame,
                  let id = row["mod_id"] as? Int else { continue }
            switch (row["status"] as? String)?.lowercased() {
            case "endorsed": map[id] = .endorsed
            case "abstained": map[id] = .abstained
            default: map[id] = .undecided
            }
        }
        return map
    }

    /// Lu quel que soit le code HTTP : une erreur typée arrive avec un 4xx.
    public static func outcome(from data: Data, httpStatus: Int) -> Outcome {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let status = (object?["status"] as? String)?.lowercased()
        let message = (object?["message"] as? String) ?? (object?["error"] as? String)
        switch (status, message?.uppercased()) {
        case ("endorsed", _): return .endorsed
        case ("abstained", _): return .abstained
        case (_, "IS_OWN_MOD"): return .isOwnMod
        case (_, "TOO_SOON_AFTER_DOWNLOAD"): return .tooSoonAfterDownload
        case (_, "NOT_DOWNLOADED_MOD"): return .notDownloaded
        default:
            let raw = message ?? String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .unknown(httpStatus: httpStatus, message: raw.flatMap { $0.isEmpty ? nil : String($0.prefix(200)) })
        }
    }
}
