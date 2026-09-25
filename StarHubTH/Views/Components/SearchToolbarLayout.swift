import SwiftUI

/// Rangée « cadrage · recherche · outils » : sur une ligne quand les trois
/// tiennent à leur largeur idéale, sinon la recherche descend seule sur la
/// seconde ligne, cadrage à gauche et outils à droite au-dessus.
///
/// ⚠️ **Un `Layout`, pas un `ViewThatFits`** : la version à deux branches
/// rendait le champ deux fois, et chaque frappe qui changeait les comptes du
/// cadrage (« Tous (966) » → « Tous (12) ») pouvait faire basculer la rangée —
/// le champ affiché était alors un autre, et le focus partait en pleine
/// saisie (2026-09-26). Ici le champ n'existe qu'une fois ; seule sa place
/// change.
///
/// Trois sous-vues, dans l'ordre : cadrage, recherche, outils. La recherche
/// reçoit la place restante (son `frame(maxWidth:)` la borne).
struct SearchToolbarLayout: Layout {
    var gap: CGFloat = AppDesign.Spacing.sm
    var lineSpacing: CGFloat = AppDesign.Spacing.sm

    private struct Arrangement {
        var oneLine: Bool
        var leading: CGSize
        var search: CGSize
        var trailing: CGSize
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> Arrangement? {
        guard subviews.count == 3 else { return nil }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        guard let width else {
            return Arrangement(oneLine: true, leading: ideal[0], search: ideal[1], trailing: ideal[2])
        }
        // Même marge que l'ancien `HStack { … Spacer() … }` : trois écarts,
        // plus le minimum du `Spacer`.
        if ideal[0].width + ideal[1].width + ideal[2].width + 3 * gap <= width {
            let room = width - ideal[0].width - ideal[2].width - 3 * gap
            let search = subviews[1].sizeThatFits(ProposedViewSize(width: room, height: nil))
            return Arrangement(oneLine: true, leading: ideal[0], search: search, trailing: ideal[2])
        }
        // Deux lignes : les outils d'abord (ils passent en icônes s'il le
        // faut), le cadrage prend le reste (il a sa forme compacte).
        let trailing = subviews[2].sizeThatFits(
            ProposedViewSize(width: max(0, width - ideal[0].width - gap), height: nil))
        let leading = subviews[0].sizeThatFits(
            ProposedViewSize(width: max(0, width - trailing.width - gap), height: nil))
        let search = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return Arrangement(oneLine: false, leading: leading, search: search, trailing: trailing)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let a = arrange(width: proposal.width, subviews: subviews) else { return .zero }
        let firstLine = max(a.leading.height, a.trailing.height, a.oneLine ? a.search.height : 0)
        let height = a.oneLine ? firstLine : firstLine + lineSpacing + a.search.height
        let naturalWidth = a.oneLine
            ? a.leading.width + a.search.width + a.trailing.width + 3 * gap
            : max(a.leading.width + gap + a.trailing.width, a.search.width)
        return CGSize(width: proposal.width ?? naturalWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        guard let a = arrange(width: bounds.width, subviews: subviews) else { return }
        let firstLine = max(a.leading.height, a.trailing.height, a.oneLine ? a.search.height : 0)
        func centered(_ size: CGSize) -> CGFloat { bounds.minY + (firstLine - size.height) / 2 }

        subviews[0].place(at: CGPoint(x: bounds.minX, y: centered(a.leading)),
                          proposal: ProposedViewSize(a.leading))
        subviews[2].place(at: CGPoint(x: bounds.maxX - a.trailing.width, y: centered(a.trailing)),
                          proposal: ProposedViewSize(a.trailing))
        if a.oneLine {
            subviews[1].place(at: CGPoint(x: bounds.minX + a.leading.width + gap, y: centered(a.search)),
                              proposal: ProposedViewSize(a.search))
        } else {
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + firstLine + lineSpacing),
                              proposal: ProposedViewSize(a.search))
        }
    }
}
