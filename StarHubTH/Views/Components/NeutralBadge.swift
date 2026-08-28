import SwiftUI

/// Pastille neutre : un mot posé sur un matériau, sans couleur porteuse de
/// sens — « FR » sur une carte de la vitrine. Distincte de `CategoryBadge`,
/// dont la teinte **est** l'information.
///
/// Les paddings 6 et 2 restent littéraux : les tokens voisins valent 4 et 8,
/// les substituer changerait l'apparence.
struct NeutralBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.fill.tertiary, in: Capsule())
    }
}
