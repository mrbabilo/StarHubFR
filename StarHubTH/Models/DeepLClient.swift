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

    // MARK: - Traduction

    public enum Outcome: Equatable, Sendable {
        case translated(String)
        /// Le quota du mois est épuisé (HTTP 456) : le secours est fini
        /// jusqu'au renouvellement de l'offre.
        case quotaExhausted
        /// Le service refuse le rythme (HTTP 429) et l'a refusé deux fois de
        /// suite. Distinct du quota : rien n'est consommé, et le message à
        /// l'utilisateur n'est pas le même — mais l'appelant coupe pareil.
        case rateLimited
        /// Le service a répondu, mais pas une traduction utilisable.
        case rejected(String)
        case transportError(String)
    }

    /// Traduit **une** source vers le français.
    ///
    /// La source part enveloppée (`TokenShield.wrap`) et la réponse revient
    /// déballée : aucun appelant ne manipule de texte enveloppé, c'est ce qui
    /// évite qu'un `<x>` finisse dans un `fr.json`.
    ///
    /// `split_sentences: "nonewlines"` et `preserve_formatting` parce que les
    /// dialogues du jeu tiennent leur sens de leurs sauts de ligne.
    ///
    /// `formality` n'est pas employé : les dialogues du jeu mêlent les
    /// registres selon le personnage, et imposer un niveau global les
    /// uniformiserait à la place du traducteur.
    public static func translate(_ source: String, context: String?,
                                 credentials: Credentials,
                                 session: URLSession,
                                 retryDelay: Duration = .seconds(2)) async -> Outcome {
        var payload: [String: Any] = [
            "text": [TokenShield.wrap(source)],
            "target_lang": "FR",
            "source_lang": "EN",
            "tag_handling": "xml",
            "ignore_tags": TokenShield.tagName,
            "preserve_formatting": true,
            "split_sentences": "nonewlines",
        ]
        if let context, !context.isEmpty { payload["context"] = context }

        var request = self.request("/v2/translate", credentials: credentials)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return .rejected("corps de requête inconstructible")
        }
        request.httpBody = body

        let first = await send(request, session: session)
        // Un 429 vaut **une** seconde tentative, temporisée. Le second refus
        // arrête là : l'appelant coupe le secours pour le reste du lot.
        guard case .rateLimited = first else { return first }
        try? await Task.sleep(for: retryDelay)
        return await send(request, session: session)
    }

    private static func send(_ request: URLRequest, session: URLSession) async -> Outcome {
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 456 { return .quotaExhausted }
            if status == 429 { return .rateLimited }
            guard status == 200 else { return .rejected("HTTP \(status)") }
            guard data.count <= maxResponseBytes,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["translations"] as? [[String: Any]],
                  let text = list.first?["text"] as? String, !text.isEmpty else {
                return .rejected("réponse illisible")
            }
            return .translated(TokenShield.unwrap(text))
        } catch {
            // Jamais la clé : `error` peut porter l'URL, pas l'en-tête.
            return .transportError("\(error)")
        }
    }
}
