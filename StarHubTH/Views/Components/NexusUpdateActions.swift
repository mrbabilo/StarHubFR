import SwiftUI

/// Les gestes d'une mise à jour Nexus due : téléchargement en cours (avec
/// annulation), « MàJ Premium », page Nexus sur ses fichiers, « Je l'ai
/// déjà », mise en veille. Sortis de la ligne de `UpdatesView` (I-T13) pour
/// que le bandeau de la fiche d'un mod porte **les mêmes** — deux copies
/// divergeraient.
struct NexusUpdateActions: View {
    let update: NexusUpdateChecker.ModUpdate
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        // Espacement de la ligne d'origine : les gestes y étaient enfants
        // directs d'un HStack(spacing: 16).
        // Icônes seules quand la place manque (fiche à 560 pt) : chaque
        // geste garde son titre en infobulle.
        AdaptiveLabels { HStack(spacing: 16) {
            if let nexusId = Int(update.nexusModId),
               vm.downloadingNexusModId == nexusId {
                // Le pourcentage à côté du témoin quand
                // la taille est connue : la ligne est le
                // seul endroit où l'on regarde après avoir
                // cliqué, et le pied de barre latérale
                // n'est pas toujours dans le champ.
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    if let percent = vm.nexusDownloadProgress?.displayPercent {
                        Text("\(percent) %")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Button(action: { vm.cancelNexusDownload() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .pointingHandCursor()
                    .help(localization.L(L10n.Downloads.cancel))
                }
                .help(localization.L(L10n.VM.nexusDlStarting).replacingOccurrences(of: "%lld", with: String(nexusId)))
            } else {
                if let nexusId = Int(update.nexusModId) {
                    Button {
                        vm.downloadModFromNexus(nexusId: nexusId)
                    } label: {
                        Label(localization.L(L10n.Mods.premiumUpdate), systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    // Désactivé quand on **sait** que le
                    // compte n'est pas premium : l'API
                    // refuse alors tout lien direct
                    // (`403 premium users only`), et
                    // proposer le bouton revient à promettre
                    // un échec. Le doute, lui, ne retire
                    // rien.
                    .disabled(vm.isDownloadingFromNexus || vm.nexusDirectDownloadUnavailable)
                    .help(localization.L(vm.nexusDirectDownloadUnavailable
                          ? L10n.Mods.premiumOnlyHint : L10n.Mods.premiumUpdate))
                }

                Button {
                    // Open the mod's Files tab directly, where the free
                    // "Mod Manager Download" (nxm://) button lives.
                    if var comps = URLComponents(string: update.url) {
                        comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "tab", value: "files")]
                        if let url = comps.url { NSWorkspace.shared.open(url) }
                    }
                } label: {
                    Label(localization.L(L10n.Mods.nexusUpdate), systemImage: "arrow.up.forward.square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .pointingHandCursor()
                .help(localization.L(L10n.Mods.nexusUpdate))
                .disabled(vm.isDownloadingFromNexus)

                // La seule sortie quand l'auteur a oublié
                // d'incrémenter son manifest : la
                // comparaison de chaînes réclamera cette
                // mise à jour à chaque passe, sinon.
                Button {
                    vm.affirmInstalled(uniqueId: update.uniqueId,
                                       version: update.latestVersion)
                } label: {
                    Label(localization.L(L10n.Updates.nexusAlreadyHave), systemImage: "checkmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .pointingHandCursor()
                .help(localization.L(L10n.Updates.nexusAlreadyHaveHelp))

                // R3 — « je sais, pas maintenant ». Troisième
                // geste après mettre à jour et « je l'ai
                // déjà » : l'update est vraie mais pas
                // voulue tout de suite. La ligne disparaît
                // d'ici (et du badge), jamais de
                // l'inventaire, et revient toute seule
                // selon le mode choisi.
                Menu {
                    Button {
                        vm.snoozeUpdate(update, mode: .oneWeek)
                    } label: {
                        Label(localization.L(L10n.Updates.snoozeOneWeek),
                              systemImage: "clock")
                    }
                    Button {
                        vm.snoozeUpdate(update, mode: .untilModVersion)
                    } label: {
                        Label(localization.L(L10n.Updates.snoozeUntilModVersion),
                              systemImage: "sparkles")
                    }
                    Button {
                        vm.snoozeUpdate(update, mode: .untilGameVersion)
                    } label: {
                        Label(localization.L(L10n.Updates.snoozeUntilGameVersion),
                              systemImage: "gamecontroller")
                    }
                } label: {
                    Label(localization.L(L10n.Updates.snoozeButton),
                          systemImage: "moon.zzz.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(6)
                }
                .help(localization.L(L10n.Updates.snoozeButton))
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointingHandCursor()
                .disabled(vm.isDownloadingFromNexus)
            }
        } }
    }
}
