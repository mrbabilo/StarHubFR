import Foundation

/// Sérialise un fichier de traduction **dans l'ordre de son auteur**.
///
/// `JSONSerialization` et `Codable [String: String]` ne garantissent aucun
/// ordre : les employer ici rendrait le fichier méconnaissable à chaque
/// enregistrement, et tout diff ultérieur illisible. L'ordre est donc fourni
/// par l'appelant, qui le tient de `I18nOutline.read(_:).orderedKeys`.
///
/// Le texte produit est **relu avant d'être rendu** : une échappée manquée
/// ferait écrire un fichier que le jeu refuserait de charger, et l'app n'aurait
/// aucun moyen de le savoir.
public enum OrderedJSONWriter {

    public enum WriteError: Error, Equatable {
        /// Le texte produit ne se relit pas à l'identique. Ne jamais l'écrire.
        case reparseMismatch
    }

    /// - Parameters:
    ///   - orderedKeys: l'ordre à respecter. Une clé absente de `values` est
    ///     **omise** — une clé non traduite doit disparaître du fichier pour
    ///     que SMAPI retombe sur `default.json` ; une chaîne vide, elle,
    ///     n'afficherait rien en jeu.
    ///   - values: les valeurs, indexées par clé.
    public static func text(orderedKeys: [String], values: [String: String]) throws -> String {
        let written = orderedKeys.filter { values[$0] != nil }
        let lines = written.map { "  \(escape($0)): \(escape(values[$0] ?? ""))" }
        let text = lines.isEmpty ? "{}\n" : "{\n\(lines.joined(separator: ",\n"))\n}\n"

        // Se relire : la seule preuve que ce qu'on s'apprête à écrire sera
        // rechargeable. Vérifié sur les valeurs **et** sur l'ordre — c'est
        // l'ordre qui se perd en silence, une valeur fautive se voit.
        let expected = Dictionary(uniqueKeysWithValues: written.map { ($0, values[$0] ?? "") })
        // `do`/`catch` plutôt que `try?` : l'échec de relecture a **une** issue
        // — refuser d'écrire — et la nommer vaut mieux que la fondre dans un
        // `nil` qui se confondrait avec « rien à faire ».
        do {
            let reparsed = try I18nLenientParser.parse(text)
            guard reparsed == expected,
                  I18nOutline.read(text).orderedKeys == written else {
                throw WriteError.reparseMismatch
            }
        } catch {
            throw WriteError.reparseMismatch
        }
        return text
    }

    /// Échappement JSON d'une chaîne, guillemets compris.
    ///
    /// À la main plutôt que par `JSONSerialization` : celle-ci n'encode pas une
    /// chaîne nue sans l'envelopper dans un conteneur, et son passage par `Any`
    /// a déjà coûté à ce dépôt (voir `ManifestJSON`).
    private static func escape(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"":  out += "\\\""
            case "\\":  out += "\\\\"
            case "\n":  out += "\\n"
            case "\r":  out += "\\r"
            case "\t":  out += "\\t"
            default:
                // Les autres caractères de contrôle passent en \uXXXX ; le
                // reste (accents, emoji, CJK) reste littéral en UTF-8.
                if c.value < 0x20 {
                    out += String(format: "\\u%04x", c.value)
                } else {
                    out.unicodeScalars.append(c)
                }
            }
        }
        return out + "\""
    }
}
