import SwiftUI

/// X103-C — les archives Nexus conservées, **regroupées par mod** : un mod
/// mis à jour plusieurs fois garde une archive par version, rangées sous son
/// nom, la plus récente en tête (`NexusArchiveGroups`, Core). Les purges
/// remontent à `MaintenanceView`, qui porte la feuille de confirmation.
///
/// La section se montre **aussi quand elle est vide**, et dit alors deux
/// choses différentes selon que la fonction est allumée ou non. Une fonction
/// éteinte par défaut qui n'expliquerait nulle part ce qu'elle fait ne serait
/// jamais découverte.
struct MaintenanceArchivesSection: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let keepNexusArchives: Bool
    let onPurgeAll: () -> Void
    let onDelete: (NexusArchiveEntry) -> Void

    var body: some View {
        if keepNexusArchives || !vm.nexusArchives.isEmpty {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                header
                if vm.nexusArchives.isEmpty {
                    Text(localization.L(keepNexusArchives
                              ? L10n.Maintenance.archivesEmptyOn
                              : L10n.Maintenance.archivesEmptyOff))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(NexusArchiveGroups.group(vm.nexusArchives)) { group in
                        groupCard(group)
                    }
                }
            }
        }
    }

    private var header: some View {
        SplitRow(spacing: AppDesign.Spacing.sm) {
            Text(localization.L(L10n.Maintenance.archivesTitle))
                .font(AppDesign.Font.body(.semibold))
        } trailing: {
            if !vm.nexusArchives.isEmpty {
                WrapHStack(spacing: AppDesign.Spacing.sm, lineSpacing: AppDesign.Spacing.xs) {
                    Text(String(format: localization.L(L10n.Maintenance.archivesCount),
                                vm.nexusArchives.count,
                                SharedFormatters.bytes(vm.nexusArchives.reduce(0) { $0 + $1.byteSize })))
                        .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                    let title = localization.L(L10n.Maintenance.archivesPurge)
                    AdaptiveLabels { Button(role: .destructive, action: onPurgeAll) {
                        Label(title, systemImage: "trash")
                    }.controlSize(.small).foregroundColor(AppDesign.Color.error).help(title) }
                }
            }
        }
    }

    /// Un mod : son nom, puis une ligne par version conservée. N-09 S17 :
    /// « Voir le mod » ouvre la fiche du mod installé sur Historique ; pas de
    /// bouton quand il n'est plus installé (aucune fiche à ouvrir).
    private func groupCard(_ group: NexusArchiveGroup) -> some View {
        let installed = group.entries.first.flatMap { vm.scanStore.mods.mod(withUniqueId: $0.uniqueId) }
        return VStack(alignment: .leading, spacing: 6) {
            SplitRow(spacing: AppDesign.Spacing.sm) {
                WrapHStack(spacing: AppDesign.Spacing.sm, lineSpacing: AppDesign.Spacing.xs) {
                    Text(group.modName).font(AppDesign.Font.caption(.semibold))
                    if let installed {
                        let title = localization.L(L10n.Health.actionOpenMod)
                        AdaptiveLabels { Button {
                            vm.navigationStore.openModDetail(folderName: installed.folderName, door: .nexusUpdate)
                        } label: { Label(title, systemImage: "arrow.up.right.square") }
                        .buttonStyle(.link).clickableCursor().focusRing(cornerRadius: 4)
                        .font(AppDesign.Font.footnote).help(title) }
                    }
                }
            } trailing: {
                if group.entries.count > 1 {
                    Text(String(format: localization.L(L10n.Maintenance.archivesVersions),
                                Int64(group.entries.count), SharedFormatters.bytes(group.totalBytes)))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                }
            }
            ForEach(group.entries) { entry in
                SplitRow(spacing: AppDesign.Spacing.sm) {
                    Text("\(entry.version) · \(SharedFormatters.bytes(entry.byteSize)) · "
                         + entry.timestamp.formatted(date: .abbreviated, time: .omitted))
                        .font(AppDesign.Font.monoIconXS)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } trailing: {
                    AdaptiveLabels { HStack(spacing: AppDesign.Spacing.sm) {
                        let reinstall = localization.L(L10n.Maintenance.archivesReinstall)
                        Button { vm.reinstallFromArchive(entry) } label: {
                            Label(reinstall, systemImage: "arrow.clockwise")
                        }.controlSize(.small).help(reinstall)
                        // E11 — le destructif à l'écart de « Réinstaller ».
                        Rectangle().fill(Color.secondary.opacity(AppDesign.Opacity.medium))
                            .frame(width: 1, height: 14)
                        let delete = localization.L(L10n.Maintenance.archivesDelete)
                        Button(role: .destructive, action: { onDelete(entry) }) {
                            Label(delete, systemImage: "trash")
                        }.controlSize(.small).foregroundColor(AppDesign.Color.error).help(delete)
                    } }
                }
            }
        }
        .padding(AppDesign.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(AppDesign.Opacity.subtle),
                    in: RoundedRectangle(cornerRadius: AppDesign.Radius.md))
    }
}
