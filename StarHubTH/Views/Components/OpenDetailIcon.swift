import SwiftUI

/// « Ouvrir la fiche » : la flèche cerclée de la page Santé du diagnostic,
/// reprise partout où une ligne mène à un mod (2026-10-08).
struct OpenDetailIcon: View {
    var body: some View {
        Image(systemName: AppDesign.openDetailSymbol)
            .font(AppDesign.Font.footnote)
            .foregroundColor(.accentColor)
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}
