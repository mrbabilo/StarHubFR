import SwiftUI

/// R8 (audit UX du 2026-10-16) — « Restaurer la configuration » à menu. Un
/// clic garde le geste d'avant (la sauvegarde la plus récente, chargée sans
/// rien écrire) ; le menu ouvre les cinq dernières versions, toutes les
/// sauvegardes du mod, et le retour aux réglages par défaut. Avant, une
/// version plus ancienne demandait six gestes dans une autre page.
struct ConfigRestoreMenu: View {
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem
    /// La même condition que le bouton de la fiche (`canManageProfileConfig`).
    let canResetDefaults: Bool
    let restoreLatest: () -> Void
    let loadVersion: (_ url: URL, _ date: String) -> Void
    let showAll: () -> Void
    let resetDefaults: () -> Void

    @State private var versions: [(id: UUID, date: String, url: URL)] = []
    @State private var confirmReset = false

    var body: some View {
        Menu {
            ForEach(versions, id: \.id) { version in
                Button(String(format: localization.L(L10n.Settings.configRestoreVersion), version.date)) {
                    loadVersion(version.url, version.date)
                }
            }
            if !versions.isEmpty { Divider() }
            Button(localization.L(L10n.Settings.configRestoreAllBackups), action: showAll)
            if canResetDefaults {
                Divider()
                Button(localization.L(L10n.Mods.profileConfigReset) + "…", role: .destructive) { confirmReset = true }
            }
        } label: {
            Label(localization.L(L10n.Settings.configRestoreConfig), systemImage: "arrow.counterclockwise")
        } primaryAction: {
            restoreLatest()
        }
        .fixedSize()
        // L'index des sauvegardes se lit hors du fil principal, une fois.
        .task(id: mod.folderName) {
            let folder = mod.folderName
            versions = await Task.detached(priority: .userInitiated) {
                ModConfigBackupManager.shared.backedUpFiles(named: "config.json", forMod: folder)
                    .prefix(5).map { (id: $0.backup.id, date: $0.backup.formattedDate, url: $0.url) }
            }.value
        }
        .confirmationDialog(localization.L(L10n.Settings.configRestoreDefaultsConfirm), isPresented: $confirmReset) {
            Button(localization.L(L10n.Mods.profileConfigReset), role: .destructive, action: resetDefaults)
        } message: {
            Text(localization.L(L10n.Mods.profileConfigResetHint))
        }
    }
}
