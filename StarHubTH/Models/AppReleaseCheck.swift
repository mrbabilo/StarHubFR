import Foundation

/// Ce que `GET /releases/latest` rend — et qui nous intéresse. L'endpoint
/// GitHub exclut déjà drafts et prereleases : pas de filtrage local.
/// Conforme `Identifiable` : le `.sheet(item:)` de l'alerte l'exige.
public struct GitHubRelease: Codable, Equatable, Identifiable, Sendable {
    public var id: String { tagName }
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body
        case htmlURL = "html_url"
    }

    public init(tagName: String, name: String?, body: String?, htmlURL: String) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
    }
}

/// La décision du checker — publiée telle quelle, l'UI ne re-décide rien.
/// `.throttled` et `.unavailable` sont des non-événements : silence au
/// lancement, message seulement sur le check manuel.
public enum AppReleaseDecision: Equatable, Sendable {
    case throttled
    case unavailable
    case upToDate
    case unparseable
    case updateAvailable(GitHubRelease, alreadySeen: Bool)
}

public enum AppReleasePolicy {

    /// TTL du check automatique — le même ordre de grandeur que smapi.io
    /// (12 h) ; GitHub anonyme tolère 60 req/h par IP, 24 h est large.
    static let checkTTL: TimeInterval = 24 * 60 * 60

    /// La décision, sans réseau. `latest == nil` (échec, 404) vaut
    /// `.unavailable` — jamais « à jour » : écrire un état faux serait pire
    /// que de n'en écrire aucun.
    public static func decide(current: String, latest: GitHubRelease?,
                              lastSeenTag: String?, lastCheckedAt: Date?,
                              now: Date, bypassThrottle: Bool) -> AppReleaseDecision {
        guard bypassThrottle
                || UpdateCheckPolicy.shouldAutoCheck(lastSuccess: lastCheckedAt,
                                                     now: now, ttl: checkTTL) else {
            return .throttled
        }
        guard let latest else { return .unavailable }
        guard isParseableTag(latest.tagName) else { return .unparseable }
        // Le comparateur du parc (`NexusUpdateChecker.compare`) gère déjà le
        // préfixe `v`/`V`, les suffixes `-pre` et `+build` et les segments
        // numériques — `1.9.0` < `1.10.0`. Rien à réinventer ici.
        switch NexusUpdateChecker.compare(latest.tagName, current) {
        case .orderedDescending:
            return .updateAvailable(latest, alreadySeen: latest.tagName == lastSeenTag)
        case .orderedSame, .orderedAscending:
            // Ascendant = l'app tourne plus neuf que la dernière release
            // (build de dev) : rien à signaler.
            return .upToDate
        }
    }

    /// Le tag a-t-il un cœur numérique lisible ? `v1.41.0` oui, `snapshot`
    /// non — un tag exotique ne doit pas pouvoir dire « à jour » : le
    /// comparateur ne sait pas échouer, la politique teste donc avant.
    static func isParseableTag(_ tag: String) -> Bool {
        var work = tag
        if work.hasPrefix("v") || work.hasPrefix("V") { work = String(work.dropFirst()) }
        if let plus = work.firstIndex(of: "+") { work = String(work[..<plus]) }
        if let dash = work.firstIndex(of: "-") { work = String(work[..<dash]) }
        let segments = work.split(separator: ".")
        guard !segments.isEmpty else { return false }
        return segments.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    /// Le premier paragraphe non vide des notes, tronqué — l'extrait de
    /// l'alerte. La release GitHub porte le reste.
    public static func firstParagraph(of markdown: String?, maxChars: Int = 280) -> String? {
        guard let markdown else { return nil }
        let paragraph = markdown
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespaces)
        guard var text = paragraph, !text.isEmpty else { return nil }
        if text.hasPrefix("#") {  // ligne de titre markdown : ce n'est pas des notes
            return nil
        }
        if text.count > maxChars {
            text = String(text.prefix(maxChars)) + "…"
        }
        return text
    }
}
