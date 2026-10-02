import SwiftUI

/// Mise en couleur de l'onglet Performances. Vert et orange disent « mieux »
/// et « moins bien » pour le joueur, rien d'autre ; jamais la couleur seule
/// (glyphe + teinte + texte, patron `SeverityBadge`). Le sens vient du Core
/// (`ProbeTrend`, testé) : un écart dans le bruit reste gris.
extension ProbeTrend {
    var tint: Color {
        switch self {
        case .better: return AppDesign.Color.success
        case .worse: return AppDesign.Color.warning
        case .neutral: return .secondary
        }
    }
}

/// La couleur d'un côté, celle des graphiques : relie une ligne de tableau
/// ou un titre à sa série.
struct PerformanceSideDot: View {
    let side: ProbeChartSide

    var body: some View {
        Circle()
            .fill(side == .before ? AppDesign.Chart.before : AppDesign.Chart.after)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

/// Une section de l'onglet dans la surface commune des cartes.
struct PerformanceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: AppDesign.Spacing.lg)
    }
}

/// Un écart chiffré : la flèche suit la valeur (monte, baisse), la teinte
/// suit le joueur (mieux, moins bien).
struct PerformanceDelta: View {
    let text: String
    let delta: Double
    let trend: ProbeTrend
    var font: Font = AppDesign.Font.footnote(.semibold)

    var body: some View {
        HStack(spacing: 2) {
            if delta != 0 {
                Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(font).monospacedDigit()
        .foregroundColor(trend.tint)
    }
}

/// Pastille : glyphe et libellé sur fond teinté.
struct PerformanceBadge: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(AppDesign.Font.caption(.medium))
            .lineLimit(1).truncationMode(.middle)
            .foregroundColor(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(AppDesign.Opacity.medium), in: Capsule())
    }
}
