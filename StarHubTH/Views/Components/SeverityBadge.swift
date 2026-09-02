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
///
/// Deux initialiseurs :
/// - `init(severity:L:)` — le cas courant, sur le patron exact de
///   `CategoryBadge` (`category:` + `L: (String) -> String`) : le libellé
///   est résolu ici même via `severity.l10nKey`, la divergence entre
///   gravité et texte devient impossible par construction.
/// - `init(severity:label:)` — pour le cas délibérément différent où le
///   libellé n'est PAS celui de la gravité (ex. tâche 9 : « Activé »/
///   « En pause » affiché *sur* une gravité). Ne pas le prendre pour le
///   cas courant.
struct SeverityBadge: View {
    let severity: HealthIssue.Severity
    let label: String

    /// Cas courant : libellé résolu depuis la gravité elle-même.
    init(severity: HealthIssue.Severity, L: (String) -> String) {
        self.severity = severity
        self.label = L(severity.l10nKey)
    }

    /// Cas délibérément différent : le libellé n'est pas celui de la
    /// gravité (voir doc de tête).
    init(severity: HealthIssue.Severity, label: String) {
        self.severity = severity
        self.label = label
    }

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
