import Foundation

/// Échappement/déchappement des entités XML pour les valeurs injectées dans
/// les fichiers de sauvegarde Stardew.
///
/// Sans cela, une ferme « D&D Farm » ou un joueur « x<y » produit un XML mal
/// formé (`&` nu invalide, `<` cassant le parse) que le lecteur rejette au
/// prochain `fetchSaves` → la save live disparaît de la liste. Data-loss sur
/// saisie légitime. Même famille que les mémoires `crlf-is-one-character` et
/// `trust-bytes-not-filenames` : faire confiance au texte brut. Audit
/// 2026-08-05, `SaveManager:540/578`.
enum XMLEntities {
    /// Échappe les 5 entités XML d'une valeur destinée au contenu d'une balise.
    /// `&` est traité en premier pour ne pas ré-échapper les `&` qu'on ajoute
    /// (`<` → `&lt;` ne doit pas devenir `&amp;lt;`).
    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Décode les 5 entités XML. `&amp;` est traité en **dernier** pour ne pas
    /// casser les autres (ex. `&amp;lt;` représente le littéral « &lt; », pas
    /// « < »).
    static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
