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
}
