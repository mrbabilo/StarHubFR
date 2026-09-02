import Foundation

/// Où chercher les champs scalaires de niveau `<SaveGame>` — `whichFarm`,
/// `goldenWalnuts`, `whichModFarm`.
///
/// **Pourquoi la queue.** Le sérialiseur du jeu écrit les scalaires de
/// `<SaveGame>` **après** ses grandes collections. Mesuré sur les 6 fichiers
/// de save du disque (2 à 39 Mo) : `<whichFarm>` et `<goldenWalnuts>` sont
/// uniques et vivent dans le dernier 1,2 % du fichier (98,8 % au pire).
/// Les chercher sur le fichier entier coûtait ~313 ms **chacun**, soit près
/// d'une seconde par sauvegarde, à chaque rafraîchissement de la page Parties.
///
/// **Pourquoi une ancre.** Restreindre la recherche est un pari sur la forme
/// du fichier ; l'ancre le vérifie au lieu de le supposer. Si la queue ne
/// contient pas `<whichFarm>`, c'est qu'on n'a pas attrapé la bonne zone et
/// l'appelant repart du fichier entier — le résultat ne peut donc pas être
/// pire qu'avant. À l'inverse, une balise absente d'une queue **qui porte
/// l'ancre** est absente de `<SaveGame>` : elle en serait la voisine.
///
/// ⚠️ Ne pas remplacer la regex de l'ancre par `range(of:)` : mesuré sur la
/// save de 37 Mo, `range(of:)` est trois fois plus lent que la regex, et
/// `utf8.firstRange(of:)` quarante fois. Voir `extractModFarmName`.
public enum SaveGameFields {

    /// Un vingtième du fichier, au moins 1 Mo : quatre fois la marge du pire
    /// cas mesuré (1,2 %), et un plancher pour les petites sauvegardes.
    public static let tailFraction = 20
    public static let tailMinimum = 1_000_000

    /// - Returns: la fin du fichier quand elle porte `<anchor>` ; le fichier
    ///   entier s'il est plus court que la fenêtre ; `nil` si l'ancre est
    ///   introuvable — à l'appelant de repartir du texte complet.
    /// - Parameter minimumWindow: le plancher de la fenêtre. Paramétrable pour
    ///   que les tests exercent la règle sans fabriquer une fixture d'un mégaoctet.
    public static func trailingScope(of xml: String, anchor: String,
                                     minimumWindow: Int = tailMinimum) -> String? {
        let window = max(minimumWindow, xml.count / tailFraction)
        let scope = window < xml.count ? String(xml.suffix(window)) : xml
        return contains(tag: anchor, in: scope) ? scope : nil
    }

    private static func contains(tag: String, in text: String) -> Bool {
        // `escapedPattern` : le nom d'ancre vient de l'appelant, un métacaractère
        // y ferait échouer la compilation — et l'ancre muette ferait repartir
        // du fichier entier en silence, c'est-à-dire annulerait le gain.
        let pattern = "<" + NSRegularExpression.escapedPattern(for: tag) + ">"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
