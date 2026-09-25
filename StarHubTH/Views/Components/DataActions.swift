import SwiftUI

// Actions ponctuelles sorties des Réglages le 2026-09-25 (revue de la page,
// décision de l'auteur) : ce ne sont pas des réglages, et elles vivent
// désormais sur l'écran de leur objet.

/// Barre d'outils de « Sauvegardes du jeu » : ouvrir le dossier des parties,
/// et en faire un zip sur le Bureau.
struct SavesDataActions: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        Button(action: { vm.openSavesFolder() }) {
            Image(systemName: "folder").font(AppDesign.Font.caption)
        }
        .buttonStyle(.bordered)
        .iconHelp(localization.L(L10n.Settings.savesFolder))

        Button(action: { vm.backupAllSaves() }) {
            Image(systemName: "archivebox").font(AppDesign.Font.caption)
        }
        .buttonStyle(.bordered)
        .iconHelp(localization.L(L10n.Settings.hintCompressSaves))
    }
}

/// Bandeau d'« Entretien » : mettre les mods en pause à la corbeille des
/// mods, et zipper le dossier Mods sur le Bureau. Toujours visible, quel que
/// soit l'état du rapport d'entretien.
struct MaintenanceModActions: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var targets: [String] = []
    @State private var confirming = false

    var body: some View {
        AdaptiveLabels {
            HStack(spacing: AppDesign.Spacing.sm) {
                Button(role: .destructive) {
                    targets = vm.disabledModTargets()
                    // Rien à mettre à la corbeille : le dire, plutôt qu'ouvrir
                    // une alerte destructive qui n'emporterait rien.
                    if targets.isEmpty {
                        vm.showModal(message: localization.L(L10n.VM.cleanModsNotFound))
                    } else {
                        confirming = true
                    }
                } label: {
                    Label(localization.L(L10n.Settings.clearDisabledMods), systemImage: "trash")
                }
                .help(localization.L(L10n.Settings.clearDisabledMods))

                Button(action: { vm.backupAllMods() }) {
                    Label(localization.L(L10n.Settings.backupMods), systemImage: "archivebox")
                }
                .help(localization.L(L10n.Settings.hintCompressMods))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, AppDesign.Spacing.sm)
        // La corbeille des mods est restaurable depuis cet écran même : la
        // confirmation chiffre ce qui part avant le clic.
        .alert(localization.L(L10n.Settings.clearDisabledMods), isPresented: $confirming) {
            Button(localization.L(L10n.Settings.deleteJunkMods), role: .destructive) {
                vm.cleanDisabledMods(targets: targets)
            }
            Button(localization.L(L10n.Saves.cancel), role: .cancel) { }
        } message: {
            Text(String(format: localization.L(L10n.Settings.clearDisabledConfirmCount),
                        Int64(targets.count)))
        }
    }
}
