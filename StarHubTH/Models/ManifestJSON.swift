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
    ///
    /// C'est la porte pour **juger** un manifeste — décider d'une installation,
    /// d'une réparation, d'une écriture. Pour lire un mod **déjà en place**,
    /// voir `decodeInstalled(_:)`, plus tolérant.
    public static func decode(_ raw: String) -> [String: Any]? {
        guard let data = sanitize(raw).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    /// Décode le manifeste d'un mod **déjà installé**, en laissant
    /// `JSONSerialization` faire tout le travail en JSON5.
    ///
    /// Le scan n'a pas de décision à prendre : SMAPI a chargé ce mod, la liste
    /// doit le montrer avec son nom et sa version. `.json5Allowed` accepte donc
    /// strictement plus que `decode(_:)` — mesuré le 2026-09-10 : clé non
    /// quotée, chaîne en quote simple, nombre hexadécimal et `Infinity` passent
    /// ici et sont refusés là ; **l'inverse n'existe pas**, aucune forme que
    /// `decode` accepte n'échoue ici.
    ///
    /// ⚠️ Le scan appliquait avant une expression régulière
    /// (`/\*[\s\S]*?\*/`) pour retirer les commentaires bloc. Elle était
    /// **inutile** — JSON5 les gère, imbriqués et en fin de fichier compris —
    /// et **nuisible** : une expression régulière ne peut pas être consciente
    /// des chaînes, si bien qu'une description contenant `/* … */` perdait son
    /// milieu en silence. Aucun des 1 108 manifestes du parc n'était touché (47
    /// portent un commentaire bloc, aucun dans une valeur), d'où un défaut
    /// latent et non un incident.
    ///
    /// - Throws: l'erreur de `JSONSerialization`, ou une erreur de racine
    ///   non-objet. L'appelant journalise : un manifeste illisible laisse un mod
    ///   sans métadonnées à l'écran, ce qui doit être explicable.
    public static func decodeInstalled(_ raw: String) throws -> [String: Any] {
        guard let data = raw.data(using: .utf8) else {
            throw NSError(domain: "StarHubFR.Manifest", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "manifeste non convertible en UTF-8"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed])
                as? [String: Any] else {
            throw NSError(domain: "StarHubFR.Manifest", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "racine non objet JSON"])
        }
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
