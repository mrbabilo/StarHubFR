import Foundation

/// Single source of truth for Nexus Mods API request construction.
///
/// All Nexus API calls (`/v1/games/.../mods/...`) must go through here so the
/// `User-Agent`, `Application-Name`, and `Application-Version` headers stay
/// consistent across the app. Previously these headers were duplicated in
/// `NexusUpdateChecker` (stuck at "1.0.9") and `NexusDownloader` ("1.1.0"),
/// which made Nexus see two different clients for the same app and produced
/// wrong usage statistics.
///
/// The app version is read live from the bundle's `CFBundleShortVersionString`
/// so it stays correct after every release bump.
enum NexusRequestBuilder {
    /// Nexus Mods public API base URL.
    static let apiBase = "https://api.nexusmods.com/v1"

    /// Game domain used for every Nexus call in this app.
    static let gameDomain = "stardewvalley"

    /// Identifiant **numérique** du jeu, tel que l'API GraphQL v2 l'exige.
    ///
    /// Lu sur `/v1/games/stardewvalley.json`. Il vit ici, à côté du domaine,
    /// parce que la recherche v2 filtre sur lui et **pas** sur le domaine :
    /// `gameDomainName` seul rend `totalCount: 0` sans la moindre erreur, ce
    /// qui ferait passer une panne pour « aucun résultat ».
    static let gameId = 1303

    /// Point d'entrée de l'API GraphQL v2, la seule à savoir chercher un mod
    /// par son nom (la v1 n'a pas de `search`). Non documentée publiquement.
    static let graphQLURL = "https://api.nexusmods.com/v2/graphql"

    /// App version read from the bundle (e.g. "1.8.0"). Falls back to "1.0"
    /// when running outside a bundle (unit tests, swift run).
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "1.0"
    }

    /// App name surfaced to Nexus via `Application-Name`. Matches the
    /// `service` Keychain identifier (without the team prefix).
    static let appName = "StarHubTH"

    /// Public repo URL, exposed in `User-Agent` per Nexus's recommendation.
    static let repoURL = "https://github.com/AppleBoiy/StarHubTH"

    /// `User-Agent` header value, e.g. `StarHubTH/1.8.0 (+https://...)`.
    static var userAgent: String {
        "\(appName)/\(appVersion) (+\(repoURL))"
    }

    /// Builds a GET `URLRequest` for the given Nexus API path, with the
    /// standard set of headers (apikey, User-Agent, Application-Name,
    /// Application-Version, Accept). Returns `nil` if the resulting URL is
    /// invalid, so callers can route to their `.failure(...)` branch instead
    /// of crashing.
    ///
    /// - Parameters:
    ///   - path: Path relative to `apiBase`, starting with `/` (e.g.
    ///     `/games/stardewvalley/mods/123.json`).
    ///   - apiKey: User's personal Nexus API key.
    static func makeRequest(path: String, apiKey: String) -> URLRequest? {
        guard let url = URL(string: apiBase + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(appName, forHTTPHeaderField: "Application-Name")
        req.setValue(appVersion, forHTTPHeaderField: "Application-Version")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    /// Construit la requête POST de l'API GraphQL v2, avec les mêmes en-têtes
    /// d'identification que les appels v1 — c'est la raison d'être de ce
    /// fichier : un second jeu d'en-têtes ferait voir deux clients à Nexus.
    static func makeGraphQLRequest(body: Data, apiKey: String) -> URLRequest? {
        guard let url = URL(string: graphQLURL) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(appName, forHTTPHeaderField: "Application-Name")
        req.setValue(appVersion, forHTTPHeaderField: "Application-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    /// `true` si `modId` est un identifiant Nexus valide (entier strictement
    /// positif). Un modId vient d'un `UpdateKey` de manifest (« nexus:191 »),
    /// source externe non fiable : sans cette garde, interpoler un `modId` comme
    /// « ../games/fallout4 » ou « 191?fields=… » dans `/games/.../mods/\(modId).json`
    /// ferait du path traversal ou de l'injection de query dans l'API. `Int(_:)`
    /// rejette tout ce qui n'est pas un entier ASCII, et la borne `> 0` écarte
    /// zéro et les négatifs (aucun modId Nexus n'est ≤ 0).
    static func isValidModId(_ modId: String) -> Bool {
        Int(modId).map { $0 > 0 } ?? false
    }
}
