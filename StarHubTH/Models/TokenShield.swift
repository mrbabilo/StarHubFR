import Foundation

/// Enveloppe les marques du jeu dans une balise que le service de traduction a
/// pour consigne d'ignorer (`tag_handling: xml` + `ignore_tags`), et défait
/// l'enveloppe au retour.
///
/// Sans elle, un moteur générique traduit `{{ContentPatcher}}` et déforme
/// `%kid1` : il n'a aucune notion de ce que le jeu lit. C'est le cœur du
/// secours en ligne — l'appel HTTP, lui, est banal.
///
/// Le découpage vient de `TranslationTokens`, seule définition d'une marque
/// dans ce dépôt, dont les segments concaténés rendent exactement la source.
public enum TokenShield {
    /// Courte à dessein : elle voyage dans chaque requête.
    public static let tagName = "x"

    public static func wrap(_ source: String) -> String {
        TranslationTokens.split(source).map { segment in
            segment.isCode
                ? "<\(tagName)>\(escape(segment.text))</\(tagName)>"
                : escape(segment.text)
        }.joined()
    }

    /// Retire les balises et déséchappe. Ne réinsère **jamais** une marque
    /// absente : la vérification est a posteriori, par `TranslationTokenCheck`.
    /// Une balise mal fermée est retirée sans emporter le texte qui suit.
    public static func unwrap(_ translated: String) -> String {
        var out = translated
        for tag in ["<\(tagName)>", "</\(tagName)>"] {
            out = out.replacingOccurrences(of: tag, with: "")
        }
        return unescape(out)
    }

    /// L'ordre compte : l'esperluette d'abord, sinon on échapperait celles
    /// qu'on vient d'écrire.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// L'inverse, et davantage : l'aller n'écrit que trois entités, mais la
    /// requête part en XML, donc la **réponse** peut en porter n'importe
    /// laquelle. Une `&quot;` non déchiffrée atterrirait telle quelle dans un
    /// `fr.json`, sans que rien ne le signale.
    ///
    /// `&amp;` se déchiffre en dernier, sans quoi une entité écrite en toutes
    /// lettres dans la source (`&quot;` comme texte, donc `&amp;quot;` sur le
    /// fil) se ferait déchiffrer deux fois et reviendrait en `"`.
    private static func unescape(_ text: String) -> String {
        var out = text
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"),
                                    ("&quot;", "\""), ("&apos;", "'")] {
            out = out.replacingOccurrences(of: entity, with: character)
        }
        out = decodeNumericReferences(out)
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    /// `&#39;` et `&#x27;` — les deux formes numériques. Une référence qu'on
    /// ne sait pas lire est laissée telle quelle : mieux vaut un `&#x110000;`
    /// visible qu'un caractère inventé.
    private static func decodeNumericReferences(_ text: String) -> String {
        guard text.contains("&#") else { return text }
        var out = ""
        var rest = Substring(text)
        while let start = rest.range(of: "&#") {
            out += rest[rest.startIndex..<start.lowerBound]
            let afterHash = rest[start.upperBound...]
            guard let end = afterHash.firstIndex(of: ";") else {
                out += rest[start.lowerBound...]
                return out
            }
            let digits = afterHash[afterHash.startIndex..<end]
            let isHex = digits.first == "x" || digits.first == "X"
            let value = isHex ? UInt32(digits.dropFirst(), radix: 16)
                              : UInt32(digits, radix: 10)
            if let value, let scalar = Unicode.Scalar(value) {
                out.append(Character(scalar))
            } else {
                out += rest[start.lowerBound...end]
            }
            rest = afterHash[afterHash.index(after: end)...]
        }
        out += rest
        return out
    }
}
