import SwiftUI

// Le bloc « avertissements récurrents » de la carte de santé, à part : le
// fichier principal est au plafond de taille.
extension SmapiHealthCard {

    /// Les mods dont les `WARN` se répètent (`SmapiDiagnostics.recurringWarnings`).
    /// Information, pas alerte : la carte ne passe pas au rouge pour eux.
    ///
    /// Chaque ligne mène quelque part : la fiche du mod, ou ses lignes dans le
    /// journal. Le journal est souvent la bonne destination — SpaceCore y
    /// signale la carte manquante d'un **autre** mod, que seul le message nomme.
    var recurringWarningsBlock: some View {
        sectionCard(.secondary) {
            sectionTitle(localization.L(L10n.Logs.healthWarnings),
                         icon: "exclamationmark.bubble.fill", color: .orange)
            Text(localization.L(L10n.Logs.healthExpWarnings))
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: AppDesignCore.Spacing.md) {
                ForEach(diagnostics.recurringWarnings) { warning in
                    recurringWarningRow(warning)
                }
            }
        }
    }

    private func recurringWarningRow(_ warning: SmapiDiagnostics.RecurringWarning) -> some View {
        VStack(alignment: .leading, spacing: AppDesignCore.Spacing.xs) {
            HStack(spacing: AppDesignCore.Spacing.sm) {
                // Le nom cède la place avant le compte : à 560 pt, « Shads
                // Context Tags Compatibility » et « 40 avertissements » ne
                // tiennent pas ensemble avec les deux boutons.
                Text(warning.mod)
                    .font(AppDesign.Font.caption(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(warning.mod)
                Text(String(format: localization.L(L10n.Logs.healthWarningsCount), Int64(warning.count)))
                    .font(AppDesign.Font.iconXS(.medium))
                    .foregroundColor(.orange)
                    .padding(.horizontal, AppDesignCore.Spacing.xs)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(AppDesignCore.Opacity.light))
                    .cornerRadius(3)
                    .fixedSize()
                Spacer(minLength: 0)
                modActions(warning.mod)
            }
            // 40 lignes qui sont 4 patches répétés 10 fois : le dire, sinon
            // le compte exagère.
            if warning.distinct < warning.count {
                Text(String(format: localization.L(L10n.Logs.healthWarningsDistinct), Int64(warning.distinct)))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
            }
            Text(warning.sample)
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .help(warning.sample)
        }
    }
}
