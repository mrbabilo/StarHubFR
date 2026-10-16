import SwiftUI

/// Une mise à jour Nexus de la page « Mise à jour des mods ». Sortie
/// d'`UpdatesView` (plafond de taille, audit UX 2026-10-16, I-T26) pour les
/// lots qui la touchent (nom vers la fiche, tri des mods en pause).
struct NexusUpdateRow: View {
    let update: NexusUpdateChecker.ModUpdate
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        let isEnabled = vm.modForNexusUpdate(update)?.isEnabled ?? false
        HStack(alignment: .top, spacing: AppDesign.Spacing.lg) {
            InitialsAvatar(
                text: update.name,
                initialsCount: 2,
                size: 44,
                fillColor: Color.accentColor.opacity(0.12),
                textColor: .accentColor,
                fontSize: 16
            )

            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                HStack(spacing: 6) {
                    // N-01b : le nom mène à la fiche, onglet Historique (journal
                    // Nexus, versions) — juger une mise à jour sans quitter l'app.
                    if let mod = vm.modForNexusUpdate(update) {
                        Button(update.name) {
                            vm.navigationStore.openModDetail(folderName: mod.folderName, door: .nexusUpdate)
                        }
                        .buttonStyle(.hoverLink)
                        .font(AppDesign.Font.rowTitle(.semibold))
                    } else {
                        Text(update.name)
                            .font(AppDesign.Font.rowTitle(.semibold))
                            .foregroundColor(.primary)
                    }
                    Text(isEnabled ? localization.L(L10n.Updates.enabled) : localization.L(L10n.Updates.disabled))
                        .font(AppDesign.Font.iconXXS(.medium))
                        .foregroundColor(isEnabled ? AppDesign.Color.installed : AppDesign.Color.warning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((isEnabled ? AppDesign.Color.installed : AppDesign.Color.warning).opacity(0.12))
                        .cornerRadius(4)
                }
                UpdateAlreadyInstalledNote(update: update, mods: vm.mods, localization: localization)
                WrapHStack(spacing: AppDesign.Spacing.md) {
                    Label("\(localization.L(L10n.Updates.installedVersion)) \(update.installedVersion)",
                          systemImage: "tag.fill")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                    Label("\(localization.L(L10n.Updates.latestVersion)) \(update.latestVersion)",
                          systemImage: "sparkles")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(AppDesign.Color.info)
                    if let uploaded = update.uploadedTime {
                        Label(vm.formatUploadedDate(uploaded),
                              systemImage: "clock.fill")
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(AppDesign.Color.dimmedSecondary(0.8))
                    }
                }
            }

            Spacer()

            NexusUpdateActions(update: update, vm: vm, localization: localization)
        }
        .padding(.vertical, AppDesign.Spacing.sm)
        .padding(.horizontal, AppDesign.Spacing.md)
        .background(isEnabled ? Color.primary.opacity(0.04) : AppDesign.Color.warning.opacity(0.06))
        .cornerRadius(10)
        .accessibilityElement(children: .contain).accessibilityLabel(update.name) // VoiceOver : groupe nommé par le mod
    }
}
