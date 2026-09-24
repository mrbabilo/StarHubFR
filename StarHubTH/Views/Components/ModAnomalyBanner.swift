import SwiftUI

/// Le bandeau d'état sous l'en-tête de la fiche d'un mod (I-T14).
///
/// La fiche s'ouvre sur la description : un mod en erreur ne le disait qu'à
/// l'onglet État, qu'il fallait penser à ouvrir. Le bandeau résume ce que la
/// pastille de la liste signale — même source, `vm.anomaly(for:)` — et mène
/// à l'onglet qui détaille. Absent quand le mod n'a rien, ou quand l'onglet
/// État est déjà ouvert.
struct ModAnomalyBanner: View {
    let anomaly: ModAnomaly
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let onShowState: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.sm) {
            SeverityBadge(severity: anomaly.severity == .error ? .critical : .warning,
                          L: localization.L)
            // Toutes les raisons, une par ligne : un mod peut cumuler une
            // dépendance manquante et des erreurs.
            Text(anomalyReasons(anomaly, vm: vm))
                .font(AppDesign.Font.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(localization.L(L10n.Mods.anomalySeeState), action: onShowState)
                .controlSize(.small)
        }
        .frame(maxWidth: 700)
        .padding(.horizontal, 24)
        .padding(.vertical, AppDesign.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background((anomaly.severity == .error ? AppDesign.Color.error : AppDesign.Color.warning)
            .opacity(AppDesign.Opacity.light))
        .overlay(alignment: .bottom) { Divider() }
    }
}
