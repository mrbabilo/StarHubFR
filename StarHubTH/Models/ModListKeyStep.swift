import Foundation

/// Où va la sélection de la liste des mods quand on presse une flèche (I-T6).
///
/// Pur, sans SwiftUI — testé dans Core. L'ordre reçu est le cadrage complet
/// que la liste vient de rendre (filtres, tri, recherche), pas la page
/// affichée : descendre depuis le dernier mod d'une page passe à la page
/// suivante, et la page à afficher est rendue avec le mod.
///
/// Sans sélection (ou une sélection sortie du cadrage), ↓ prend le premier
/// mod de la page affichée et ↑ le dernier : on part de ce qu'on voit, pas du
/// début d'une liste de 1 000 mods.
public enum ModListKeyStep {
    public enum Move: Sendable { case previous, next, first, last }

    /// `nil` quand rien ne bouge : liste vide, ou déjà au bout.
    public static func target(from current: String?, move: Move, in order: [String],
                              currentPage: Int, pageSize: Int) -> (folderName: String, page: Int)? {
        guard !order.isEmpty, pageSize > 0 else { return nil }
        let index: Int
        switch (move, current.flatMap { order.firstIndex(of: $0) }) {
        case (.first, _):
            index = 0
        case (.last, _):
            index = order.count - 1
        case (.next, let i?):
            guard i + 1 < order.count else { return nil }
            index = i + 1
        case (.previous, let i?):
            guard i > 0 else { return nil }
            index = i - 1
        case (.next, nil), (.previous, nil):
            let pageStart = min(max(0, (currentPage - 1) * pageSize), order.count - 1)
            let pageEnd = min(pageStart + pageSize, order.count) - 1
            index = move == .next ? pageStart : pageEnd
        }
        return (order[index], index / pageSize + 1)
    }
}
