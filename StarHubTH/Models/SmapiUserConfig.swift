import Foundation

/// `smapi-internal/config.user.json` : les réglages de l'auteur que SMAPI
/// fusionne sur `config.json` (`JsonConvert.PopulateObject`, SMAPI 4.5.2). On
/// n'y touche qu'une liste, `ModsToLoadEarly`, par **édition textuelle
/// minimale** — commentaires, ordre des clés et BOM restent ceux de l'auteur.
/// Un texte qui ne se relit pas comme un objet JSON n'est jamais réécrit.
public enum SmapiUserConfig {
    private static let key = "ModsToLoadEarly"
    private static let bom = "\u{FEFF}"

    public static func listsLoadEarly(_ text: String?, modId: String) -> Bool {
        guard let text, let list = loadEarly(in: text) else { return false }
        return list.ids.contains { $0.caseInsensitiveCompare(modId) == .orderedSame }
    }

    /// Le nouveau texte, ou nil : rien à changer, ou texte illisible.
    public static func settingLoadEarly(_ text: String?, modId: String, present: Bool) -> String? {
        let raw = text ?? ""
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard present else { return nil }
            return "{\n  \"\(key)\": [\"\(modId)\"]\n}\n"
        }
        guard isObject(raw) else { return nil }
        let listed = listsLoadEarly(raw, modId: modId)
        guard listed != present else { return nil }

        let out: String
        if let list = loadEarly(in: raw) {
            var ids = list.ids
            if present {
                ids.append(modId)
            } else {
                ids.removeAll { $0.caseInsensitiveCompare(modId) == .orderedSame }
            }
            let inner = ids.map { "\"\($0)\"" }.joined(separator: ", ")
            out = raw.replacingCharacters(in: list.contents, with: inner)
        } else {
            // Clé absente (seul cas « ajout » ici : un retrait l'aurait vue listée).
            guard let brace = raw.firstIndex(of: "{") else { return nil }
            let after = raw.index(after: brace)
            let rest = raw[after...].trimmingCharacters(in: .whitespacesAndNewlines)
            let separator = rest.hasPrefix("}") ? "" : ","
            out = raw.replacingCharacters(in: after..<after,
                                          with: "\n  \"\(key)\": [\"\(modId)\"]\(separator)")
        }
        return isObject(out) ? out : nil
    }

    // MARK: — Privé

    /// La liste et l'intervalle de son contenu (entre `[` et `]`). Limites
    /// assumées : les identifiants de mods ne portent ni `,` ni `]` ni
    /// guillemet échappé — un fichier exotique est traité comme illisible
    /// (aucune écriture) plutôt que corrompu.
    private static func loadEarly(in text: String) -> (ids: [String], contents: Range<String.Index>)? {
        let pattern = "\"\(key)\"\\s*:\\s*\\[([^\\]]*)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let inner = Range(match.range(at: 1), in: text) else { return nil }
        let ids = text[inner].split(separator: ",").compactMap { part -> String? in
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") else { return nil }
            return String(trimmed.dropFirst().dropLast())
        }
        return (ids, inner)
    }

    /// Objet JSON lisible, commentaires et BOM tolérés (lecture de SMAPI : Newtonsoft).
    private static func isObject(_ text: String) -> Bool {
        let body = text.hasPrefix(bom) ? String(text.dropFirst()) : text
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) else { return false }
        return object is [String: Any]
    }
}
