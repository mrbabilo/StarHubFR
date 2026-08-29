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
        return findBoldOpener(in: blocks)
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

    /// **Rang 2 : un passage en gras seul sur sa ligne**, à défaut de titre.
    ///
    /// Mesuré : 19 fiches de plus sur 200, et 3 écartées parce que le gras y est
    /// noyé dans une phrase. Beaucoup des 19 sont des questions de FAQ
    /// (« Is this compatible with SVE? ») qui ouvrent bel et bien une section.
    ///
    /// Le découpage se fait **à la ligne, dans le Markdown d'un bloc `.text`** :
    /// un tel bloc porte tout le texte entre deux éléments structurels — neuf
    /// lignes sur la fiche qui a servi de modèle.
    private static func findBoldOpener(in blocks: [DescriptionBlock]) -> CompatibilityNote? {
        for (index, block) in blocks.enumerated() {
            guard case .text(let markdown) = block else { continue }
            let lines = markdown.components(separatedBy: "\n")
            guard let opener = lines.firstIndex(where: {
                isBoldAlone($0) && mentionsCompatibility($0)
            }) else { continue }

            // Le reste du bloc, jusqu'au prochain gras isolé.
            var tail: [String] = []
            for line in lines[(opener + 1)...] {
                if isBoldAlone(line) { break }
                tail.append(line)
            }
            var body: [DescriptionBlock] = []
            let rest = tail.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { body.append(.text(rest)) }

            // Puis les blocs suivants, jusqu'à un titre ou un nouveau gras isolé.
            if tail.count == lines.count - opener - 1 {
                for next in blocks[(index + 1)...] {
                    if case .heading = next { break }
                    if case .text(let md) = next {
                        let followingLines = md.components(separatedBy: "\n")
                        if let boldIdx = followingLines.firstIndex(where: isBoldAlone) {
                            // Il y a un gras isolé : on prend le texte d'avant et on s'arrête
                            let beforeBold = followingLines[..<boldIdx].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !beforeBold.isEmpty {
                                body.append(.text(beforeBold))
                            }
                            break
                        }
                        body.append(next)
                    } else {
                        body.append(next)
                    }
                }
            }
            guard !body.isEmpty else { continue }
            return CompatibilityNote(heading: clean(lines[opener]), blocks: body)
        }
        return nil
    }

    /// Une ligne faite d'un seul passage en gras, et de rien d'autre.
    /// `**Compatibility:**` oui ; `il **inclut** ceci` non.
    private static func isBoldAlone(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("**"), trimmed.hasSuffix("**"), trimmed.count > 4
        else { return false }
        let inner = trimmed.dropFirst(2).dropLast(2)
        return !inner.contains("**")
    }
}
