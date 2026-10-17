import SwiftUI

// Actions ponctuelles sorties des Réglages le 2026-09-25 (revue de la page,
// décision de l'auteur) : ce ne sont pas des réglages, et elles vivent
// désormais sur l'écran de leur objet.

/// Barre d'outils de « Sauvegardes du jeu » : ouvrir le dossier des parties,
/// et en faire un zip là où l'utilisateur le choisit (`FolderArchiveSheet`).
struct SavesDataActions: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var archive: FolderArchiveRequest?

    var body: some View {
        Button(action: { vm.openSavesFolder() }) {
            Image(systemName: "folder").font(AppDesign.Font.caption)
        }
        .buttonStyle(.bordered).focusRing()
        .iconHelp(localization.L(L10n.Settings.savesFolder))

        Button(action: { archive = .saves(localization) }) {
            Image(systemName: "archivebox").font(AppDesign.Font.caption)
        }
        .buttonStyle(.bordered).focusRing()
        .iconHelp(localization.L(L10n.Settings.hintCompressSaves))
        .sheet(item: $archive) { FolderArchiveSheet(localization: localization, request: $0) }
    }
}

/// Bandeau d'« Entretien » : mettre les mods en pause à la corbeille des
/// mods, et zipper tout le dossier Mods — mods en pause compris — là où
/// l'utilisateur le choisit (`FolderArchiveSheet`). Toujours visible, quel que
/// soit l'état du rapport d'entretien.
struct MaintenanceModActions: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var targets: [String] = []
    @State private var confirming = false
    @State private var archive: FolderArchiveRequest?

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
                .help(localization.L(L10n.Settings.clearDisabledMods)).focusRing(cornerRadius: 5)

                Button(action: archiveMods) {
                    Label(localization.L(L10n.Settings.backupMods), systemImage: "archivebox")
                }
                .help(localization.L(L10n.Settings.hintCompressMods)).focusRing(cornerRadius: 5)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppDesign.Spacing.xl)
        .padding(.vertical, AppDesign.Spacing.sm)
        .sheet(item: $archive) { FolderArchiveSheet(localization: localization, request: $0) }
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

    /// Sans jeu désigné, pas de `Mods/` à archiver : le dire plutôt qu'ouvrir
    /// une feuille vide.
    private func archiveMods() {
        guard let request = FolderArchiveRequest.mods(from: vm, localization) else {
            vm.showModal(message: localization.L(L10n.Settings.gameDirNotSet))
            return
        }
        archive = request
    }
}
