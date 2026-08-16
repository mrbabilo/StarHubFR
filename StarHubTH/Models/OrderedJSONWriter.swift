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
        /// L'ordre porte deux fois la même clé. `I18nOutline.read` en produit
        /// sciemment — un `fr.json` écrit à la main avec une clé recopiée
        /// suffit. Refuser, plutôt que de laisser `Dictionary` trapper et tuer
        /// l'app sur le fichier d'un traducteur.
        case duplicateKey(String)
        /// Une valeur à écrire n'a aucun rang dans l'ordre fourni. La garde ne
        /// pouvait pas le voir : elle se comparait au sous-ensemble que
        /// l'écrivain avait lui-même retenu, si bien que le travail disparaissait
        /// en silence, relecture verte à l'appui.
        case valueWithoutOrder(String)
    }

    /// - Parameters:
    ///   - orderedKeys: l'ordre à respecter, **sans doublon**. Une clé sans
    ///     valeur, ou de valeur vide, est **omise** — elle doit disparaître du
    ///     fichier pour que SMAPI retombe sur `default.json` ; une chaîne vide,
    ///     elle, n'afficherait rien en jeu.
    ///   - values: les valeurs, indexées par clé. Chacune, si elle n'est pas
    ///     vide, doit avoir son rang dans `orderedKeys`.
    ///
    /// - Note: `$schema`, que le parseur et `I18nOutline` écartent tous deux,
    ///   ne peut pas traverser cet écrivain : un fichier qui en portait un le
    ///   perd à l'enregistrement. Le rétablir demande de lever cette exclusion
    ///   des deux côtés à la fois, sans quoi la garde de relecture le prendrait
    ///   pour une corruption.
    public static func text(orderedKeys: [String], values: [String: String]) throws -> String {
        var seen = Set<String>()
        for key in orderedKeys {
            guard seen.insert(key).inserted else { throw WriteError.duplicateKey(key) }
        }
        // Toute valeur non vide doit avoir un rang. Sans cette vérification, une
        // clé fraîchement traduite — présente dans la source, pas encore dans le
        // fichier cible d'où vient l'ordre — était écartée sans un mot.
        for (key, value) in values where !value.isEmpty && !seen.contains(key) {
            throw WriteError.valueWithoutOrder(key)
        }

        let written = orderedKeys.filter { !(values[$0] ?? "").isEmpty }
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
                // Les caractères de contrôle C0 passent en \uXXXX — seuls
                // ceux-là doivent l'être. U+007F et les C1 sont légaux nus en
                // JSON, comme les accents, les emoji et le CJK, et restent
                // littéraux en UTF-8.
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
