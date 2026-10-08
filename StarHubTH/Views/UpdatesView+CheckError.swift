import SwiftUI

/// Une vérification en échec (2026-10-08 : smapi.io en panne, HTTP 500) :
/// la cause, l'âge de la liste affichée s'il y en a une, et l'alternative —
/// vérifier directement sur Nexus, au choix de l'utilisateur.
struct UpdateCheckFailureBanner: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let error: String
    /// Une liste en cache est affichée dessous : dire qu'elle date d'avant.
    let listIsStale: Bool

    private var message: String {
        let cause = switch error {
        case "rate_limited": localization.L(L10n.Updates.nexusRateLimited)
        case "server_down": localization.L(L10n.Updates.smapiServerDown)
        default: localization.L(L10n.Updates.nexusError)
        }
        return listIsStale ? cause + " " + localization.L(L10n.Updates.checkFailedStale) : cause
    }

    var body: some View {
        let pages = viewModel.nexusAlternativePages
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            Text(message)
                .font(AppDesign.Font.caption)
                .foregroundColor(AppDesign.Color.error.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            if pages > 0 {
                if viewModel.hasNexusApiKey {
                    Button(localization.L(L10n.Updates.nexusAlternativeButton)) {
                        viewModel.checkUpdatesViaNexus()
                    }
                    .controlSize(.small)
                    Text(String(format: localization.L(L10n.Updates.nexusAlternativeHint), Int64(pages)))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(localization.L(L10n.Updates.nexusAlternativeNoKey))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

/// Arrête une vérification en cours (2026-10-08) : tout de suite pendant
/// smapi.io, à la page suivante pendant la reprise Nexus.
struct UpdateCheckStopButton: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        let stopping = viewModel.updateStopRequested
        Button(localization.L(stopping ? L10n.Updates.checkStopping : L10n.Updates.checkStop)) {
            viewModel.stopUpdateCheck()
        }
        .controlSize(.small)
        .disabled(stopping)
    }
}
