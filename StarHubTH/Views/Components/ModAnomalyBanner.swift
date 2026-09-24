import SwiftUI

/// Le bandeau d'état sous l'en-tête de la fiche d'un mod (I-T14).
///
/// La fiche s'ouvre sur la description : un mod en erreur ne le disait qu'à
/// l'onglet État, qu'il fallait penser à ouvrir. Le bandeau résume ce que la
/// pastille de la liste signale — même source, `vm.anomaly(for:)` — et mène
/// à l'onglet qui détaille. Absent quand le mod n'a rien, ou quand l'onglet
/// État est déjà ouvert : celui-ci porte alors `ModAnomalyCard`.
struct ModAnomalyBanner: View {
    let anomaly: ModAnomaly
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let onShowState: () -> Void

    var body: some View {
        ModAnomalySummary(anomaly: anomaly, vm: vm, localization: localization,
                          actionTitle: localization.L(L10n.Mods.anomalySeeState),
                          action: onShowState)
            .frame(maxWidth: 700)
            .padding(.horizontal, 24)
            .padding(.vertical, AppDesign.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(anomaly.tint.opacity(AppDesign.Opacity.light))
            .overlay(alignment: .bottom) { Divider() }
    }
}

/// Le même résumé en tête de l'onglet État. Sans lui, un doublon, un
/// manifeste sans identifiant ou une dépendance manquante allumaient la
/// pastille et le bandeau, puis l'onglet État n'en disait rien : aucune de
/// ses sections ne les porte (constaté sur `[APF] Tactical Echo Mines NPCs`,
/// installé une seconde fois dans `TacticalEchoMines/assets/`).
struct ModAnomalyCard: View {
    let anomaly: ModAnomaly
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// Mène à l'onglet Dépendances — le seul signal dont le détail vit ailleurs.
    let onShowDependencies: () -> Void

    var body: some View {
        ModAnomalySummary(anomaly: anomaly, vm: vm, localization: localization,
                          actionTitle: anomaly.hasDependencyIssue
                              ? localization.L(L10n.Profiles.dependencies) : nil,
                          action: onShowDependencies)
            .padding(AppDesign.Spacing.md)
            .background(anomaly.tint.opacity(AppDesign.Opacity.light),
                        in: RoundedRectangle(cornerRadius: AppDesign.Radius.section))
    }
}

/// Gravité, toutes les raisons (une par ligne : un mod peut cumuler une
/// dépendance manquante et des erreurs), et un geste facultatif.
private struct ModAnomalySummary: View {
    let anomaly: ModAnomaly
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.sm) {
            SeverityBadge(severity: anomaly.severity == .error ? .critical : .warning,
                          L: localization.L)
            Text(anomalyReasons(anomaly, vm: vm))
                .font(AppDesign.Font.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
    }
}

private extension ModAnomaly {
    var tint: Color { severity == .error ? AppDesign.Color.error : AppDesign.Color.warning }
}
