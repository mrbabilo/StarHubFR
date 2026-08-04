import Foundation

/// Decision about whether/how to reconcile a mod's manifest after a Nexus install.
enum ManifestVersionDecision: Equatable {
    case correctVersion(to: String)  // installed version is lower → rewrite it
    case refreshDate                 // same/undecidable version, newer Nexus upload → touch mtime
    case noChange                    // nothing to do
}

/// Pure logic for reconciling a mod's `manifest.json` against the Nexus file it
/// was installed from. No I/O, no networking → unit-tested. The version
/// comparator is injected because the app's semver compare
/// (`NexusUpdateChecker.isNewer`) lives outside the Core module.
enum ManifestVersionPatcher {

    /// `manifestModified` is the installed manifest.json's on-disk mtime — the
    /// same value the update checker compares against the Nexus upload date.
    static func decide(nexusVersion: String,
                       nexusUploaded: Date?,
                       manifestVersion: String?,
                       manifestModified: Date?,
                       isNewer: (String, String) -> Bool) -> ManifestVersionDecision {
        guard !nexusVersion.isEmpty else { return .noChange }

        if let manifestVersion = manifestVersion, !manifestVersion.isEmpty {
            if isNewer(nexusVersion, manifestVersion) {
                return .correctVersion(to: nexusVersion)   // author forgot to bump
            }
            if isNewer(manifestVersion, nexusVersion) {
                return .noChange                           // never downgrade
            }
            // Equal version strings fall through to the date check below.
        }

        // Equal or undecidable version: a minor update without a version bump.
        // Touch the manifest mtime so the checker (Nexus upload > mtime) stops
        // flagging it — but only when the Nexus upload is actually newer.
        if let up = nexusUploaded, let m = manifestModified, up > m {
            return .refreshDate
        }
        return .noChange
    }

    /// Regex matching a string-form `"Version": "…"` entry (key case-insensitive,
    /// tolerant of surrounding whitespace). Group 1 = the value.
    // Case-insensitive on the key ("Version"/"version"/"VERSION"): the opening
    // quote must sit immediately before the token, so longer keys like
    // "MinimumApiVersion" never match. Group 2 = the string value.
    private static let versionStringRegex = try! NSRegularExpression(
        pattern: #"("Version"\s*:\s*")([^"]*)(")"#, options: [.caseInsensitive])

    static func extractVersionValue(from raw: String) -> String? {
        // Lire la `Version` comme le fait le scanner (JSON5, commentaires
        // inclus), pas par regex sur le texte brut : un `"Version"` laissé en
        // commentaire (usage courant en JSONC chez les mods Stardew) était
        // matché avant la vraie valeur. Les commentaires de bloc ne sont pas
        // fiablement gérés par `.json5Allowed` — on les retire d'abord, à
        // l'identique de `ModFolderRepairer`. La forme dictionnaire
        // `{MajorVersion,…}` ressort `nil` (échec du `as? String`), comme la
        // regex.
        let cleaned = raw.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "",
                                               options: .regularExpression)
        var options: JSONSerialization.ReadingOptions = []
        if #available(macOS 12.0, *) { options.insert(.json5Allowed) }
        guard let data = cleaned.data(using: .utf8) else { return nil }
        do {
            guard let json = try JSONSerialization.jsonObject(with: data, options: options) as? [String: Any] else {
                return nil
            }
            return json.caseInsensitiveValue(forKey: "Version") as? String
        } catch {
            return nil
        }
    }

    /// Replaces ONLY the string value of the `Version` field, leaving everything
    /// else byte-for-byte. Returns nil when no string-form Version field exists
    /// (dict form / absent) → caller must abstain.
    static func replaceVersionValue(in raw: String, with newVersion: String) -> String? {
        let range = NSRange(raw.startIndex..., in: raw)
        guard let m = versionStringRegex.firstMatch(in: raw, range: range) else { return nil }
        let escaped = NSRegularExpression.escapedTemplate(for: newVersion)
        // Replace only the first match's range, so extract and replace always
        // agree on which occurrence is the mod's version.
        return versionStringRegex.stringByReplacingMatches(
            in: raw, range: m.range, withTemplate: "$1\(escaped)$3")
    }
}
