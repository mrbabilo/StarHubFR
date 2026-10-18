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
        SplitRow(spacing: AppDesign.Spacing.lg) {
            InitialsAvatar(text: update.name, initialsCount: 2, size: 44,
                           fillColor: Color.accentColor.opacity(AppDesign.Opacity.light),
                           textColor: .accentColor, fontSize: 16)
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                HStack(spacing: 6) {
                    // N-01b : le nom mène à la fiche, onglet Historique (journal
                    // Nexus, versions) — juger une mise à jour sans quitter l'app.
                    if let mod = vm.modForNexusUpdate(update) {
                        Button(update.name) {
                            vm.navigationStore.openModDetail(folderName: mod.folderName, door: .nexusUpdate)
                        }
                        .buttonStyle(.link).clickableCursor().focusRing(cornerRadius: 4)
                        .font(AppDesign.Font.rowTitle(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .help(update.name)
                    } else {
                        Text(update.name)
                            .font(AppDesign.Font.rowTitle(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .help(update.name)
                    }
                    // C1a : la pause n'est pas un avertissement — gris, avec son
                    // glyphe (jamais la couleur seule), comme dans la liste.
                    let tint = isEnabled ? AppDesign.Color.installed : AppDesign.Color.paused
                    Label(localization.L(isEnabled ? L10n.Updates.enabled : L10n.Updates.disabled),
                          systemImage: isEnabled ? "checkmark.circle.fill" : "pause.circle.fill")
                        .font(AppDesign.Font.iconXXS(.medium))
                        .foregroundColor(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.12))
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
        } trailing: {
            NexusUpdateActions(update: update, vm: vm, localization: localization)
        }
        .padding(.vertical, AppDesign.Spacing.sm)
        .padding(.horizontal, AppDesign.Spacing.md)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(10)
        .accessibilityElement(children: .contain).accessibilityLabel(update.name) // VoiceOver : groupe nommé par le mod
    }
}

/// P5-6a — les mises à jour Nexus, mods actifs d'abord, mods en pause dans un
/// groupe replié. Replié, jamais retiré : une mise à jour voulue avant de
/// réactiver un mod reste à un clic, avec son compte affiché.
struct NexusUpdateList: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// Hors de la vue, pour la même raison que `updates.unverifiableExpanded` :
    /// la page est recréée à chaque retour depuis une fiche.
    @AppStorage("updates.pausedExpanded") private var pausedExpanded = false

    var body: some View {
        let groups = NexusUpdateGroups(viewModel.nexusUpdates) { viewModel.modForNexusUpdate($0)?.isEnabled }
        // I-T33 — les rangées hors écran ne participent plus à chaque passe
        // de layout quand la barre latérale anime la largeur du contenu.
        LazyVStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            // Sans mise à jour en pause, l'en-tête n'apprendrait rien.
            if !groups.paused.isEmpty, !groups.active.isEmpty {
                Text(String(format: localization.L(L10n.Updates.activeGroup), Int64(groups.active.count)))
                    .font(AppDesign.Font.caption(.semibold))
                    .foregroundColor(.secondary)
            }
            ForEach(groups.active) { update in
                NexusUpdateRow(update: update, vm: viewModel, localization: localization)
            }
            if !groups.paused.isEmpty {
                DisclosureGroup(isExpanded: $pausedExpanded) {
                    LazyVStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                        Text(localization.L(L10n.Updates.pausedGroupExplanation))
                            .font(AppDesign.Font.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(groups.paused) { update in
                            NexusUpdateRow(update: update, vm: viewModel, localization: localization)
                        }
                    }
                    .padding(.vertical, AppDesign.Spacing.xs)
                } label: {
                    Label(String(format: localization.L(L10n.Updates.pausedGroup), Int64(groups.paused.count)),
                          systemImage: "pause.circle.fill")
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
