import SwiftUI

/// Une colonne de chiffre clé, hors de sa bande : libellé `footnote`
/// au-dessus, valeur `body` semibold en dessous. Le motif `StatStrip`
/// réduit à la colonne — pour les rangées de liste où la bande entière
/// et ses respirations ne tiennent pas.
///
/// `attention` pose glyph **et** couleur (P6) : un état ne tient jamais à
/// la couleur seule, et une colonne sans données affiche « — » à hauteur
/// tenue — la rangée ne saute pas (P4).
struct StatColumn: View {
    let label: String
    let value: String
    var attention: Bool = false
    /// Le texte entier quand la colonne tronque ; vide = pas d'infobulle
    /// (patron du dépôt : `help("")` n'affiche rien).
    var help: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary)
            HStack(spacing: AppDesign.Spacing.xs) {
                if attention {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppDesign.Font.iconXXS)
                        .foregroundColor(AppDesign.Color.warning)
                }
                Text(value)
                    .font(AppDesign.Font.body(.semibold))
                    .foregroundColor(attention ? AppDesign.Color.warning : .primary)
                    .lineLimit(1)
            }
        }
        .help(help)
    }
}
