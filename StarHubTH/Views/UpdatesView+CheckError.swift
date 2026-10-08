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

/// Les mods sans verdict de mise à jour, ni smapi.io ni Nexus (2026-10-08) :
/// le bilan des deux passes, puis la raison **finale** de chaque mod — celle
/// de la reprise Nexus quand elle a eu lieu, sinon celle de smapi.io, qui
/// reste en infobulle.
struct UnverifiableModsSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        let rows = viewModel.unverifiableMods
        let summary = viewModel.unverifiableSummary
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 3) {
                if summary.nexus > 0 {
                    Text(String(format: localization.L(L10n.Updates.unverifiableSummary),
                                Int64(summary.smapi), Int64(summary.nexus), Int64(rows.count)))
                        .font(AppDesign.Font.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                }
                // Indexé par `UniqueID` : deux mods peuvent porter le même nom,
                // et la reprise Nexus retire des lignes en cours de route.
                ForEach(rows, id: \.uniqueId) { row in
                    HStack(spacing: 6) {
                        // La fiche s'ouvre sur Santé : c'est là qu'on saisit
                        // l'identifiant Nexus qui manque (2026-10-08).
                        if let mod = viewModel.scanStore.mods.mod(withUniqueId: row.uniqueId) {
                            Button {
                                viewModel.navigationStore.openModDetail(folderName: mod.folderName)
                            } label: {
                                Image(systemName: "info.circle")
                                    .frame(width: 18, height: 18)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .help(localization.L(L10n.Mods.openDetails))
                            .accessibilityLabel(localization.L(L10n.Mods.openDetails) + " — " + row.name)
                        }
                        Text(row.name)
                            .font(AppDesign.Font.footnote(.medium))
                        Text(localization.L(row.outcome?.labelKey ?? row.blocker.labelKey))
                            .font(AppDesign.Font.footnote)
                            .foregroundStyle(.secondary)
                            .help(localization.L(row.blocker.labelKey))
                        Spacer(minLength: 8)
                    }
                }
            }
            .padding(.vertical, AppDesign.Spacing.xs)
        } label: {
            Label(String(format: localization.L(L10n.Updates.unverifiableTitle), Int64(rows.count)),
                  systemImage: "exclamationmark.triangle.fill")
                .font(AppDesign.Font.caption)
                .foregroundColor(AppDesign.Color.warning)
        }
    }
}
