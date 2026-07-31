import Foundation

/// Prépare un `manifest.json` de mod pour `JSONSerialization`.
///
/// SMAPI accepte le JSON5, et **son propre modèle de manifeste** est livré avec
/// des commentaires `//` et une virgule traînante. Beaucoup d'auteurs les
/// gardent tels quels : un mod parfaitement valide pour le jeu était donc
/// refusé à l'installation avec « manifest.json manquant » — le manifeste était
/// bien là, il ne se décodait simplement pas.
///
/// L'analyse est **consciente des chaînes**, ce qu'une expression régulière ne
/// peut pas être : les manifestes contiennent des URL, et retirer `//` sans
/// distinguer le contexte transformerait `"https://example.com"` en `"https:`.
public enum ManifestJSON {
    /// Retire marque d'ordre des octets, commentaires et virgules traînantes.
    public static func sanitize(_ raw: String) -> String {
        stripTrailingCommas(stripComments(raw.replacingOccurrences(of: "\u{FEFF}", with: "")))
    }

    /// Décode un manifeste, ou `nil` s'il reste indécodable après nettoyage.
    /// Refuse les fragments : un manifeste est un objet, pas une valeur nue.
    public static func decode(_ raw: String) -> [String: Any]? {
        guard let data = sanitize(raw).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private static func stripComments(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var inString = false, escaped = false
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if inString {
                out.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i = s.index(after: i)
                continue
            }
            if c == "\"" { inString = true; out.append(c); i = s.index(after: i); continue }
            if c == "/", s.index(after: i) < s.endIndex {
                let next = s[s.index(after: i)]
                if next == "/" {
                    // Jusqu'à la fin de ligne, saut de ligne conservé pour ne
                    // pas fusionner deux lignes.
                    while i < s.endIndex, !s[i].isNewline { i = s.index(after: i) }
                    continue
                }
                if next == "*" {
                    i = s.index(i, offsetBy: 2)
                    while i < s.endIndex {
                        if s[i] == "*", s.index(after: i) < s.endIndex, s[s.index(after: i)] == "/" {
                            i = s.index(i, offsetBy: 2)
                            break
                        }
                        i = s.index(after: i)
                    }
                    continue
                }
            }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }

    private static func stripTrailingCommas(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var inString = false, escaped = false
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if inString {
                out.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i = s.index(after: i)
                continue
            }
            if c == "\"" { inString = true; out.append(c); i = s.index(after: i); continue }
            if c == "," {
                // Regarder au-delà des espaces : une virgule suivie d'une
                // fermeture est traînante.
                var j = s.index(after: i)
                while j < s.endIndex, s[j].isWhitespace { j = s.index(after: j) }
                if j < s.endIndex, s[j] == "}" || s[j] == "]" {
                    i = s.index(after: i)   // virgule sautée, espaces conservés
                    continue
                }
            }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }
}
