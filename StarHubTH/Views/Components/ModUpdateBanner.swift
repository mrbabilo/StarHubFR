import SwiftUI

/// Le bandeau « mise à jour disponible » de la fiche d'un mod (I-T13), sous
/// celui des anomalies (ordre de gravité, I-T16).
///
/// Même index que la pastille de la liste et le badge de la barre latérale.
/// Une ligne Nexus porte les gestes de la page Mises à jour
/// (`NexusUpdateActions`, le même composant) ; une entrée du relevé SMAPI
/// n'a qu'un lien smapi.io, comme sur cette page.
struct ModUpdateBanner: View {
    let pending: PendingModUpdates.Pending
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Label(String(format: localization.L(L10n.Updates.availableVersion), pending.availableVersion),
                  systemImage: "arrow.up.circle.fill")
                .font(AppDesign.Font.caption(.medium))
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
            switch pending.source {
            case .nexus(let uniqueId):
                // La ligne d'origine, pour ses gestes ; introuvable si la
                // liste vient de changer — le bandeau disparaît au rendu suivant.
                if let update = vm.nexusUpdates.first(where: { $0.uniqueId == uniqueId }) {
                    NexusUpdateActions(update: update, vm: vm, localization: localization)
                        .controlSize(.small)
                }
            case .smapi(let url):
                Button(localization.L(L10n.Updates.openSmapiPage)) {
                    if let link = URL(string: url) { NSWorkspace.shared.open(link) }
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: 700)
        .padding(.horizontal, 24)
        .padding(.vertical, AppDesign.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(Color.blue.opacity(AppDesign.Opacity.light))
        .overlay(alignment: .bottom) { Divider() }
    }
}
