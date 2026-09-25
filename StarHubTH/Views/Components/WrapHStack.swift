import SwiftUI

/// Une rangée qui passe à la ligne quand la place manque, au lieu de
/// déborder.
///
/// Tant que tout tient, elle se comporte comme un `HStack` (centré
/// verticalement, même espacement). Sinon elle reporte l'élément suivant sur
/// une nouvelle ligne : un élément à largeur figée (les colonnes de
/// `ModListRow`) reste entier, et toutes les lignes de la liste, qui portent
/// les mêmes largeurs, se replient au même endroit — les colonnes restent
/// alignées d'une ligne à l'autre. Un élément plus large que la rangée à lui
/// seul reçoit la largeur disponible (un texte `lineLimit(1)` s'y tronque).
///
/// Né du constat du 2026-09-25 (I-T11) : à la fenêtre minimale, la bande
/// d'informations d'un mod mesurait ~590 pt pour ~260 disponibles et
/// décentrait toute la liste. Pas de `Spacer` dedans : il n'y a pas de sens
/// ici, c'est un conteneur qui n'étire rien.
struct WrapHStack: Layout {
    var spacing: CGFloat = AppDesign.Spacing.sm
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(limit: proposal.width, subviews: subviews)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +)
            + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(limit: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for (index, size) in zip(line.indices, line.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(limit: CGFloat?, subviews: Subviews) -> [Line] {
        let limit = limit ?? .infinity
        var lines: [Line] = []
        var current = Line()
        for index in subviews.indices {
            let ideal = subviews[index].sizeThatFits(.unspecified)
            let width = min(ideal.width, limit)
            let size = width < ideal.width
                ? subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
                : ideal
            if !current.indices.isEmpty, current.width + spacing + size.width > limit {
                lines.append(current)
                current = Line()
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
            current.sizes.append(size)
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }
}
