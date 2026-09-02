import SwiftUI

/// Badge de gravité pour un `HealthIssue` : glyphe **et** couleur **et**
/// libellé.
///
/// Jamais la couleur seule (critère d'accessibilité 2 de la refonte santé/
/// secours) : un daltonien doit lire la gravité, une capture en niveaux de
/// gris aussi. Trois gravités, trois formes de glyphe distinctes (octogone
/// plein, triangle plein, cercle) — la couleur renforce, elle ne porte
/// jamais seule l'information.
///
/// `exclamationmark.octagon.fill` est déjà utilisé ailleurs dans le dépôt
/// (`ModListView.swift`) sur cette même cible macOS 14 : le symbole existe,
/// pas de repli triangle nécessaire pour la gravité critique.
struct SeverityBadge: View {
    let severity: HealthIssue.Severity
    let label: String

    private var glyph: String {
        switch severity {
        case .critical: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle"
        }
    }

    private var tint: Color {
        switch severity {
        case .critical: return AppDesign.Color.error
        case .warning: return AppDesign.Color.warning
        case .info: return AppDesign.Color.secondary
        }
    }

    var body: some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Image(systemName: glyph)
                .font(AppDesign.Font.caption)
            Text(label)
                .font(AppDesign.Font.caption(.medium))
        }
        .foregroundColor(tint)
    }
}
