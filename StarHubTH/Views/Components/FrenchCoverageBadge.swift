import SwiftUI

/// Pastille de couverture française, dans le vocabulaire de `VersionBadge` :
/// une unité compacte et scannable plutôt qu'un mot noyé dans la ligne grise.
///
/// **Le nombre porte l'information, la couleur la renforce** — jamais
/// l'inverse. Un badge dont le sens tiendrait au seul vert contre orange serait
/// illisible pour un daltonien et invisible en balayage rapide ; c'est le taux
/// écrit qui se compare d'une ligne à l'autre.
///
/// Trois états, parce qu'il y en a trois : mesuré et complet, mesuré et
/// partiel, et **pas encore mesuré** — le calcul se fait en tâche de fond après
/// le scan. Ce dernier état se lit en gris et sans nombre : annoncer un taux
/// qu'on ignore serait pire que de ne rien annoncer.
struct FrenchCoverageBadge: View {
    /// `nil` tant que la mesure n'a pas abouti.
    let percent: Int?
    let unmeasuredLabel: String
    let percentFormat: String

    private var tint: Color {
        guard let percent else { return .secondary }
        return percent >= 100 ? AppDesign.Color.success : .orange
    }

    var body: some View {
        Text(percent.map { String(format: percentFormat, $0) } ?? unmeasuredLabel)
            // Chiffres à chasse fixe : dans une liste, « 8 % » et « 72 % »
            // doivent s'aligner verticalement pour se comparer d'un coup d'œil,
            // sinon chaque pastille danse d'une ligne à l'autre.
            .font(AppDesign.Font.iconXS(.semibold).monospacedDigit())
            // Sur une seule ligne, quoi qu'il arrive : dans une colonne de
            // largeur fixe, « FR 100 % » se repliait et poussait le « % » sous
            // le reste. `fixedSize` prime sur la contrainte de la colonne.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(tint.opacity(AppDesign.Opacity.medium))
            )
            .overlay(
                // Un liseré porte le contour que l'aplat à 15 % ne donne pas —
                // sans lui la pastille se dissout sur un fond clair.
                Capsule().stroke(tint.opacity(AppDesign.Opacity.strong), lineWidth: 0.5)
            )
    }
}

// Partagée par la ligne de liste et la bande fine de la fiche (2026-09-25).
