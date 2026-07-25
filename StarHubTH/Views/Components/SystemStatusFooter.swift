import SwiftUI

// SystemStatusFooter.swift
// Résumé compact affiché en bas du sidebar (avant le Spacer final).
// Visible en permanence, donne un aperçu immédiat de l'état du système
// sans nécessiter de clic vers l'onglet "Alertes".
//
// Trois indicateurs :
//   - Mods actifs (vert) : nombre de mods activés / total
//   - Updates (orange)   : mises à jour SMAPI + Nexus disponibles
//   - Errors (rouge)     : erreurs SMAPI détectées (masqué si 0)

struct SystemStatusFooter: View {
    @ObservedObject var vm: StarHubTHViewModel

    private var enabledCount: Int { vm.mods.filter(\.isEnabled).count }
    private var updatesCount: Int { vm.outOfDateMods.count + vm.nexusUpdates.count }
    private var errorsCount: Int { vm.smapiErrors.count }

    var body: some View {
        HStack(spacing: AppDesign.Spacing.md) {
            statusPill(
                count: enabledCount,
                total: vm.mods.count,
                color: AppDesign.Color.success,
                icon: "puzzlepiece.extension"
            )
            statusPill(
                count: updatesCount,
                color: AppDesign.Color.warning,
                icon: "arrow.up.circle"
            )
            if errorsCount > 0 {
                statusPill(
                    count: errorsCount,
                    color: AppDesign.Color.error,
                    icon: "exclamationmark.triangle"
                )
            }
        }
        .padding(.horizontal, AppDesign.Spacing.sm)
        .padding(.vertical, AppDesign.Spacing.xs)
        .accessibilityLabel(
            String(
                format: vm.L(L10n.Main.systemStatusA11y),
                Int64(enabledCount),
                Int64(updatesCount),
                Int64(errorsCount)
            )
        )
    }

    /// Un indicateur compact : icône + compteur. La couleur reflète l'état
    /// (vert si tout va bien, orange/rouge si attention requise).
    private func statusPill(
        count: Int,
        total: Int? = nil,
        color: Color,
        icon: String
    ) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(AppDesign.Font.iconXS)
            if let total = total {
                Text("\(count)/\(total)")
                    .font(AppDesign.Font.footnote(.medium))
                    .monospacedDigit()
            } else {
                Text("\(count)")
                    .font(AppDesign.Font.footnote(.medium))
                    .monospacedDigit()
            }
        }
        // Vert seulement si tout est actif (count == total) ; orange sinon
        // pour les updates ; rouge pour les erreurs.
        .foregroundColor(displayColor(count: count, total: total, base: color))
    }

    /// Détermine la couleur d'affichage selon le contexte :
    /// - Mods : vert si tous actifs, sinon gris discret
    /// - Updates/Errors : couleur d'alerte si count > 0, sinon gris discret
    private func displayColor(count: Int, total: Int?, base: Color) -> Color {
        if let total = total {
            // Cas "mods actifs" : vert si tout est activé, sinon discret
            return count == total && total > 0 ? base : AppDesign.Color.secondary
        } else {
            // Cas updates/errors : couleur si count > 0, sinon discret
            return count > 0 ? base : AppDesign.Color.secondary
        }
    }
}
