import SwiftUI

/// L'idiome `HStack { gauche ; Spacer() ; droite }`, qui se replie sur deux
/// lignes au lieu de déborder quand la fenêtre est trop étroite : la partie
/// gauche en premier, la droite dessous, calée à droite comme avant.
///
/// Né de la revue de tous les écrans du 2026-09-25 (I-T11) : à la fenêtre
/// minimale, plusieurs rangées de boutons textuels demandaient 520 à 640 pt
/// pour ~500 — des boutons ne rétrécissent pas, ils tronquent ou poussent la
/// page hors de la fenêtre. Pour une rangée sans partie droite, `WrapHStack`.
///
/// ⚠️ **Un `Layout`, jamais un `ViewThatFits`** (2026-09-26). La première
/// version rendait chaque partie deux fois, une par disposition : passer de
/// l'une à l'autre remplaçait les vues. Un champ de texte y perdait le focus
/// dès que sa frappe changeait la largeur de la rangée (le ✕ d'effacement qui
/// apparaît au premier caractère suffit). Ici chaque partie existe une seule
/// fois, et seule sa place change.
struct SplitRow<Leading: View, Trailing: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        SplitRowLayout(gap: spacing ?? AppDesign.Spacing.sm) {
            HStack(spacing: spacing) { leading() }
            HStack(spacing: spacing) { trailing() }
        }
    }
}

/// Deux sous-vues : gauche et droite. Sur une ligne quand leurs largeurs
/// idéales tiennent (même test que `ViewThatFits`), sinon la droite passe
/// dessous, calée à droite.
struct SplitRowLayout: Layout {
    var gap: CGFloat
    var lineSpacing: CGFloat = AppDesign.Spacing.sm

    private struct Arrangement {
        var oneLine: Bool
        var leading: CGSize
        var trailing: CGSize
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> Arrangement {
        guard subviews.count == 2 else {
            return Arrangement(oneLine: true, leading: .zero, trailing: .zero)
        }
        let leadingIdeal = subviews[0].sizeThatFits(.unspecified)
        let trailingIdeal = subviews[1].sizeThatFits(.unspecified)
        guard let width else {
            return Arrangement(oneLine: true, leading: leadingIdeal, trailing: trailingIdeal)
        }
        if leadingIdeal.width + gap + trailingIdeal.width <= width {
            // Ce qui reste va à la gauche d'abord (un champ de recherche s'y
            // étire), puis à la droite si la gauche ne l'a pas pris.
            let leading = subviews[0].sizeThatFits(
                ProposedViewSize(width: width - gap - trailingIdeal.width, height: nil))
            let trailing = subviews[1].sizeThatFits(
                ProposedViewSize(width: width - gap - leading.width, height: nil))
            return Arrangement(oneLine: true, leading: leading, trailing: trailing)
        }
        let proposal = ProposedViewSize(width: width, height: nil)
        return Arrangement(oneLine: false,
                           leading: subviews[0].sizeThatFits(proposal),
                           trailing: subviews[1].sizeThatFits(proposal))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let a = arrange(width: proposal.width, subviews: subviews)
        if a.oneLine {
            return CGSize(width: proposal.width ?? (a.leading.width + gap + a.trailing.width),
                          height: max(a.leading.height, a.trailing.height))
        }
        return CGSize(width: proposal.width ?? max(a.leading.width, a.trailing.width),
                      height: a.leading.height + lineSpacing + a.trailing.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let a = arrange(width: bounds.width, subviews: subviews)
        if a.oneLine {
            let height = max(a.leading.height, a.trailing.height)
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + (height - a.leading.height) / 2),
                              proposal: ProposedViewSize(a.leading))
            subviews[1].place(at: CGPoint(x: bounds.maxX - a.trailing.width,
                                          y: bounds.minY + (height - a.trailing.height) / 2),
                              proposal: ProposedViewSize(a.trailing))
        } else {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY),
                              proposal: ProposedViewSize(a.leading))
            subviews[1].place(at: CGPoint(x: bounds.maxX - a.trailing.width,
                                          y: bounds.minY + a.leading.height + lineSpacing),
                              proposal: ProposedViewSize(a.trailing))
        }
    }
}
