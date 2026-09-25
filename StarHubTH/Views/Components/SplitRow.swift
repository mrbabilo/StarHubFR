import SwiftUI

/// L'idiome `HStack { gauche ; Spacer() ; droite }`, qui se replie sur deux
/// lignes au lieu de déborder quand la fenêtre est trop étroite : la partie
/// gauche en premier, la droite dessous, calée à droite comme avant.
///
/// Né de la revue de tous les écrans du 2026-09-25 (I-T11) : à la fenêtre
/// minimale, plusieurs rangées de boutons textuels demandaient 520 à 640 pt
/// pour ~500 — des boutons ne rétrécissent pas, ils tronquent ou poussent la
/// page hors de la fenêtre. Pour une rangée sans partie droite, `WrapHStack`.
struct SplitRow<Leading: View, Trailing: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                leading()
                Spacer(minLength: spacing ?? AppDesign.Spacing.sm)
                trailing()
            }
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                HStack(spacing: spacing) { leading() }
                HStack(spacing: spacing) {
                    Spacer(minLength: 0)
                    trailing()
                }
            }
        }
    }
}
