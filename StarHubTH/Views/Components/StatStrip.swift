import SwiftUI

/// Une bande de chiffres clés : ce qui décide avant la prose. Sur une fiche de
/// mod, endossements, version, âge de la mise à jour et catégorie tranchent
/// l'installation plus sûrement qu'un paragraphe de description.
///
/// Les colonnes se partagent la largeur à parts égales, quel qu'en soit le
/// nombre.
struct StatStrip: View {
    struct Item: Identifiable {
        let label: String
        let value: String
        /// Le texte entier de la valeur quand la colonne tronque (76
        /// caractères de codes de langue mesurés sur le parc réel) — nil,
        /// pas d'infobulle.
        var help: String? = nil
        /// Le libellé identifie la colonne : deux colonnes d'une même bande
        /// n'ont jamais le même intitulé.
        var id: String { label }
    }

    let items: [Item]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(AppDesign.Font.footnote)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(AppDesign.Font.body(.semibold))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .helpIfPresent(item.help)
            }
        }
        .padding(.horizontal, AppDesign.Spacing.lg)
        .padding(.vertical, AppDesign.Spacing.md)
    }
}

/// Une infobulle qui n'existe que si son texte existe : ce SDK n'offre pas
/// de surcharge `help(_:)` optionnelle, et une infobulle vide sur une
/// colonne sans `help` serait un parasite de survol.
@MainActor
private extension View {
    @ViewBuilder
    func helpIfPresent(_ text: String?) -> some View {
        if let text { help(text) } else { self }
    }
}
