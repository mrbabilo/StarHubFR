import Foundation

/// La section « Compatibility » qu'un auteur a écrite dans sa description Nexus.
///
/// **On affiche sa phrase, on n'en déduit rien.** Mesuré sur 200 descriptions
/// réelles : 30 mentionnent une incompatibilité, mais un repérage automatique des
/// paires n'aurait que 20 % de précision — 24 des 30 désignent une catégorie
/// (« tout mod qui modifie la carte des égouts ») ou sont des négations
/// (« There are no known mod conflicts »). Remonter le paragraphe et laisser
/// juger est le seul usage honnête d'un signal aussi bruité.
///
/// Portée `internal` : `DescriptionBlock` l'est déjà, et la cible de test importe
/// `@testable`.
struct CompatibilityNote: Equatable {
    /// Le titre, nettoyé de son Markdown et de ses résidus HTML.
    let heading: String
    /// Le corps de la section, tel que le parseur l'a produit.
    let blocks: [DescriptionBlock]

    /// La première section de compatibilité, `nil` s'il n'y en a pas.
    ///
    /// **Rang 1 : un titre.** `DescriptionBlockParser` ne fabrique un `.heading`
    /// que depuis `[heading]` ou `[size=N]` avec N ≥ 4 — mesuré : 41 fiches sur
    /// 200. La section court jusqu'au titre suivant de niveau **égal ou
    /// supérieur** ; comme 1 est le plus grand et 3 le plus petit, cela s'écrit
    /// `level <= opening`.
    static func find(in blocks: [DescriptionBlock]) -> CompatibilityNote? {
        for (index, block) in blocks.enumerated() {
            guard case .heading(let raw, let opening) = block,
                  mentionsCompatibility(raw) else { continue }
            var body: [DescriptionBlock] = []
            for next in blocks[(index + 1)...] {
                if case .heading(_, let level) = next, level <= opening { break }
                body.append(next)
            }
            guard !body.isEmpty else { continue }
            return CompatibilityNote(heading: clean(raw), blocks: body)
        }
        return nil
    }

    /// Sans accents ni casse — un titre français dit « Compatibilité ».
    static func mentionsCompatibility(_ text: String) -> Bool {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .contains("compatib")
    }

    /// Le corps d'un titre garde le Markdown que le parseur y a mis, et parfois
    /// du HTML que le BBCode portait : relevé tel quel,
    /// `Who's Compatible?!\n<br />\n<br />`.
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<br />", with: " ")
            .replacingOccurrences(of: "<br/>", with: " ")
            .replacingOccurrences(of: "<br>", with: " ")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
