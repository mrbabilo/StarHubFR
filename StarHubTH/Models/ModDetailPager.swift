import Foundation

/// Les voisins d'un mod dans le cadrage ordonné de la liste : de quoi
/// parcourir la liste sans y retourner, chevrons de la fiche (H-T4b).
///
/// Pur, sans SwiftUI — testé dans Core. L'ordre reçu est l'instantané que
/// la liste vient de rendre (`ModListState.displayOrder`) : filtres, tri et
/// recherche compris. Un nom absent de l'ordre (composant de pack, mod
/// exclu par le cadrage) n'a pas de voisins — le pager s'éteint.
public enum ModDetailPager {
    public static func neighbors(of folderName: String,
                                 in order: [String]) -> (previous: String?, next: String?) {
        guard let idx = order.firstIndex(of: folderName) else { return (nil, nil) }
        return (idx > 0 ? order[idx - 1] : nil,
                idx + 1 < order.count ? order[idx + 1] : nil)
    }
}
