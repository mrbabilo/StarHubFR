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
            VStack(alignment: .leading, spacing: 10) {
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
        HStack {
            Text(localization.L(L10n.Maintenance.archivesTitle))
                .font(AppDesign.Font.body(.semibold))
            Spacer()
            if !vm.nexusArchives.isEmpty {
                Text(String(format: localization.L(L10n.Maintenance.archivesCount),
                            vm.nexusArchives.count,
                            Self.bytes(vm.nexusArchives.reduce(0) { $0 + $1.byteSize })))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
                Button(localization.L(L10n.Maintenance.archivesPurge), role: .destructive,
                       action: onPurgeAll)
                    .controlSize(.small)
                    .foregroundColor(AppDesign.Color.error)
            }
        }
    }

    /// Un mod : son nom, puis une ligne par version conservée.
    private func groupCard(_ group: NexusArchiveGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.modName)
                    .font(AppDesign.Font.caption(.semibold))
                Spacer()
                if group.entries.count > 1 {
                    Text(String(format: localization.L(L10n.Maintenance.archivesVersions),
                                Int64(group.entries.count), Self.bytes(group.totalBytes)))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                }
            }
            ForEach(group.entries) { entry in
                HStack {
                    Text("\(entry.version) · \(Self.bytes(entry.byteSize)) · "
                         + entry.timestamp.formatted(date: .abbreviated, time: .omitted))
                        .font(AppDesign.Font.monoIconXS)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(localization.L(L10n.Maintenance.archivesReinstall)) {
                        vm.reinstallFromArchive(entry)
                    }
                    .controlSize(.small)
                    Button(localization.L(L10n.Maintenance.archivesDelete), role: .destructive) {
                        onDelete(entry)
                    }
                    .controlSize(.small)
                    .foregroundColor(AppDesign.Color.error)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(AppDesignCore.Radius.md)
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
