import SwiftUI

/// Le haut commun des pages (audit UX 2026-10-02) : une tuile d'icône qui
/// reprend le symbole de la barre latérale, le titre, une ligne de contexte,
/// puis les actions. Les actions passent sous le titre quand la fenêtre est
/// trop étroite (`SplitRow`), jamais tronquées.
struct PageHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    /// Teinte de la tuile. Décorative par défaut (accent) ; une page d'état
    /// (Alertes) y met la couleur de l'état, toujours doublée d'un texte.
    var tint: Color = AppDesign.Color.accent
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        SplitRow(spacing: AppDesign.Spacing.md) {
            IconTile(icon: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppDesign.Font.viewTitle)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(AppDesign.Font.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } trailing: {
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil,
         tint: Color = AppDesign.Color.accent) {
        self.init(icon: icon, title: title, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

/// Un symbole SF sur un carré arrondi en dégradé de sa teinte. Décoratif :
/// le titre voisin dit ce que la tuile montre.
struct IconTile: View {
    let icon: String
    var tint: Color = AppDesign.Color.accent
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.7)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: tint.opacity(0.25), radius: 3, y: 1)
            .accessibilityHidden(true)
    }
}

extension View {
    /// La surface d'une carte : fond secondaire, liseré discret, ombre
    /// légère. Une seule écriture pour toutes les cartes des pages.
    func cardSurface(padding: CGFloat = AppDesign.Spacing.md) -> some View {
        self
            .padding(padding)
            .background(.background.secondary,
                        in: RoundedRectangle(cornerRadius: AppDesign.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.lg, style: .continuous)
                .stroke(Color.primary.opacity(AppDesign.Opacity.light), lineWidth: 0.5))
            .shadow(color: .black.opacity(AppDesign.Shadow.card.opacity),
                    radius: AppDesign.Shadow.card.radius, y: AppDesign.Shadow.card.y)
    }
}

/// Un chiffre clé : glyphe, valeur, libellé. Avec `action`, la tuile mène à
/// ce qu'elle résume (règle des écrans de synthèse) ; `isSelected` la marque
/// quand elle sert de filtre. Le chiffre change en roulant, sauf sous
/// « Réduire les animations ».
struct MetricTile: View {
    let icon: String
    let value: Int
    let label: String
    var tint: Color = AppDesign.Color.accent
    var isSelected = false
    var help: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .helpIfPresent(help)
        } else {
            content.helpIfPresent(help)
        }
    }

    private var content: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: icon)
                .font(AppDesign.Font.headline)
                .foregroundStyle(value > 0 ? tint : Color.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.system(size: AppDesign.Font.scaled(22), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Motion.animation(.snappy), value: value)
                Text(label)
                    .font(AppDesign.Font.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minWidth: 120, alignment: .leading)
        .contentShape(.rect)
        .cardSurface(padding: AppDesign.Spacing.sm)
        .overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.lg, style: .continuous)
            .stroke(tint, lineWidth: isSelected ? 1.5 : 0))
        .accessibilityElement(children: .combine)
    }
}
