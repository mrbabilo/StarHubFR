import Foundation

/// L'appel à DeepL, et rien de plus : l'ordre des tentatives vit dans
/// `TranslationEngine`, la protection des marques dans `TokenShield`.
public enum DeepLClient {

    /// Une clé d'API et l'hôte qu'elle désigne.
    public struct Credentials: Equatable, Sendable {
        public let key: String

        /// `nil` pour une clé vide : pas d'identifiants, donc pas de secours.
        public init?(key: String) {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            self.key = trimmed
        }

        /// Le suffixe `:fx` marque une clé du plan gratuit (documentation
        /// DeepL) — l'utilisateur n'a donc jamais à choisir son hôte.
        public var isFreePlan: Bool { key.hasSuffix(":fx") }

        public var baseURL: URL {
            // Deux hôtes constants et valides : le repli ne peut pas servir.
            URL(string: isFreePlan ? "https://api-free.deepl.com"
                                   : "https://api.deepl.com")!
        }
    }

    // MARK: - Quota

    /// Ce que le compte a consommé ce mois-ci. Le plafond vient du service :
    /// coder « 500 000 » en dur mentirait au premier changement d'offre.
    public struct Usage: Equatable, Sendable {
        public let used: Int
        public let limit: Int
        public var remaining: Int { max(limit - used, 0) }

        public init(used: Int, limit: Int) {
            self.used = used
            self.limit = limit
        }
    }

    public enum UsageError: Error, Equatable, Sendable {
        case unauthorized
        case http(Int)
        case malformed
    }

    /// Plafond du corps lu, comme pour le client local : un service qui
    /// déraille ne doit pas remplir la mémoire.
    static let maxResponseBytes = 4 << 20

    /// `appendingPathComponent` et non une concaténation : le double slash a
    /// déjà été payé une fois sur le client local.
    static func request(_ path: String, credentials: Credentials) -> URLRequest {
        var request = URLRequest(url: credentials.baseURL.appendingPathComponent(path))
        request.setValue("DeepL-Auth-Key \(credentials.key)", forHTTPHeaderField: "Authorization")
        return request
    }

    public static func usage(credentials: Credentials,
                             session: URLSession) async throws -> Usage {
        let (data, response) = try await session.data(
            for: request("/v2/usage", credentials: credentials))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw UsageError.unauthorized }
        guard status == 200 else { throw UsageError.http(status) }
        guard data.count <= maxResponseBytes,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let used = json["character_count"] as? Int,
              let limit = json["character_limit"] as? Int else {
            throw UsageError.malformed
        }
        return Usage(used: used, limit: limit)
    }
}
