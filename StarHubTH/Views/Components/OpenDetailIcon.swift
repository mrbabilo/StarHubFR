import SwiftUI

/// « Ouvrir la fiche » : la flèche cerclée de la page Santé du diagnostic,
/// reprise partout où une ligne mène à un mod (2026-10-08).
struct OpenDetailIcon: View {
    var body: some View { ActionIcon(symbol: AppDesign.openDetailSymbol) }
}

/// Le glyphe d'un bouton d'action à icône seule dans une ligne, au gabarit
/// de la page Santé : couleur d'accent, cible de 20 pt pour que l'infobulle
/// s'affiche.
struct ActionIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(AppDesign.Font.footnote)
            .foregroundColor(.accentColor)
            .frame(width: 20, height: 20)
            .contentShape(.rect)
            .accessibilityHidden(true)
    }
}
