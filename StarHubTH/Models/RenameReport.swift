import Foundation

/// C2-T4 §8.2 — appliquer des renommages aux fichiers de l'utilisateur, en
/// logique pure pour être testée. Jamais d'écrasement d'une valeur déjà
/// posée : l'abstention est par paire, une paire refusée n'empêche pas les
/// autres.
public enum RenameReport {

    /// Reporte des paires dans un texte de `fr.json` : la nouvelle clé prend
    /// la position de l'ancienne, l'ancienne disparaît. Abstention par paire
    /// si la nouvelle clé est déjà traduite (on n'écrase jamais) ou si
    /// l'ancienne n'a rien à sauver. Rend le texte réécrit et les paires
    /// réellement appliquées — texte intact et lot vide si rien ne passe.
    public static func applyToFrench(_ text: String,
                                     pairs: [RenamePair]) -> (text: String, applied: [RenamePair]) {
        guard let values = try? JSONSerialization.jsonObject(
            with: Data(text.utf8)) as? [String: String] else { return (text, []) }
        let outline = I18nOutline.read(text)

        var newValues = values
        var applied: [RenamePair] = []
        for pair in pairs {
            guard let frenchValue = values[pair.oldKey] else { continue }   // rien à sauver
            guard newValues[pair.newKey] == nil else { continue }           // déjà traduit
            newValues.removeValue(forKey: pair.oldKey)
            newValues[pair.newKey] = frenchValue
            applied.append(pair)
        }
        guard !applied.isEmpty else { return (text, []) }

        // La nouvelle clé prend la position de l'ancienne ; les clés neuves
        // sans ancêtre vont en fin.
        var ordered: [String] = []
        for key in outline.orderedKeys {
            if let replacement = applied.first(where: { $0.oldKey == key })?.newKey {
                if !ordered.contains(replacement) { ordered.append(replacement) }
            } else if newValues[key] != nil && !ordered.contains(key) {
                ordered.append(key)
            }
        }
        for key in newValues.keys.sorted() where !ordered.contains(key) { ordered.append(key) }

        guard let rewritten = try? OrderedJSONWriter.text(orderedKeys: ordered, values: newValues)
        else { return (text, []) }
        return (rewritten, applied)
    }
}
