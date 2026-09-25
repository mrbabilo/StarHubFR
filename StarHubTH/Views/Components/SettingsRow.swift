import SwiftUI

/// Une ligne de réglage : le titre, son explication **visible** dessous, et
/// le contrôle à droite.
///
/// L'explication vivait derrière une icône (i) (`InfoPopoverButton`) : il
/// fallait cliquer pour apprendre ce que fait un interrupteur avant de le
/// basculer. Revue des Réglages du 2026-09-25 : elle s'affiche désormais en
/// petit gris sous le titre, et passe à la ligne plutôt que de pousser le
/// contrôle hors de la fenêtre.
struct SettingsRow<Control: View>: View {
    let title: String
    let hint: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppDesign.Font.body)
                if !hint.isEmpty {
                    Text(hint)
                        .font(AppDesign.Font.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
    }
}
