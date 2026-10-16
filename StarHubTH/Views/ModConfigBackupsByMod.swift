import SwiftUI

/// Les sauvegardes de configuration **par mod** (`ConfigBackupBrowser`) : un
/// mod déplié montre ses versions, et chacune se restaure seule. Remarque de
/// l'auteur du 2026-10-16 — par date, une sauvegarde complète déversait ~200
/// mods, et retrouver un réglage demandait de déplier chaque date.
struct ModConfigBackupsByMod: View {
    @ObservedObject var localization: LocalizationStore
    let groups: [ConfigBackupBrowser.ModGroup]
    @Binding var expanded: Set<String>
    let restore: (ModConfigBackup, ModConfigBackupItem) -> Void
    let compare: (ConfigBackupBrowser.Version) -> Void

    var body: some View {
        BackToTopScrollView(localization) {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(groups) { group in card(group) }
            }
            .padding(AppDesign.Spacing.xl)
        }
    }

    private func card(_ group: ConfigBackupBrowser.ModGroup) -> some View {
        let isOpen = expanded.contains(group.folderName)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if isOpen { expanded.remove(group.folderName) } else { expanded.insert(group.folderName) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(AppDesign.Font.footnote(.bold)).foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.displayName).font(AppDesign.Font.body(.medium)).foregroundColor(.primary)
                        Text(subtitle(group)).font(AppDesign.Font.footnote).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain).pointingHandCursor()
            .padding(.horizontal, 14).padding(.vertical, 10)

            if isOpen {
                Divider().padding(.leading, 14)
                ForEach(group.versions) { version in
                    SplitRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(version.backup.formattedDate).font(AppDesign.Font.caption(.medium))
                            Text(version.item.files.joined(separator: ", "))
                                .font(AppDesign.Font.iconXS).foregroundColor(.secondary)
                        }
                    } trailing: {
                        if version.item.files.contains("config.json") {
                            Button(localization.L(L10n.ModConfigBackups.compare)) { compare(version) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        Button(localization.L(L10n.ModConfigBackups.restoreVersion)) {
                            restore(version.backup, version.item)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                }
                .padding(.bottom, 6)
            }
        }
        .cardSurface(padding: 0)
    }

    private func subtitle(_ group: ConfigBackupBrowser.ModGroup) -> String {
        let versions = String(format: localization.L(L10n.ModConfigBackups.versions),
                              group.versions.count, group.versions.first?.backup.formattedDate ?? "—")
        guard let parent = group.parentFolderName else { return versions }
        return versions + " — " + String(format: localization.L(L10n.ModConfigBackups.partOfGroup), parent)
    }
}
