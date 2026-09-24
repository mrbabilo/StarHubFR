import SwiftUI

/// Une rangée de boutons qui reste lisible à la largeur minimale de la
/// fenêtre (volet de détail à 560 pt) : libellés complets quand ils tiennent,
/// **icônes seules** sinon — jamais un libellé tronqué ou replié.
///
/// Contrat pour chaque bouton de la rangée (règle UI, `AGENTS.md` §6) :
/// - son libellé est un `Label(titre, systemImage:)`, que `.iconOnly` réduit ;
/// - il porte `.help(titre)` (ou une aide plus riche) : c'est l'infobulle qui
///   rend le titre quand seule l'icône reste. Le libellé d'accessibilité,
///   lui, suit le `Label` et ne se perd pas.
struct AdaptiveLabels<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content().labelStyle(.titleAndIcon)
            content().labelStyle(.iconOnly)
        }
    }
}
