import SwiftUI

// Sortie de `ModConfigBackupsView` (2026-10-16) pour lui faire place.

// MARK: - Row

struct ModConfigBackupRow: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let backup: ModConfigBackup
    /// Les éléments que la recherche laisse voir.
    let items: [ModConfigBackupItem]
    let isExpanded: Bool
    @Binding var selectedItemIds: Set<UUID>
    let onToggleExpand: () -> Void
    let onRestoreSelected: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onToggleExpand) {
                    HStack(spacing: 10) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(AppDesign.Font.footnote(.bold))
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(backup.formattedDate)
                                .font(AppDesign.Font.body(.medium))
                                .foregroundColor(.primary)
                            Text("\(String(format: localization.L(L10n.ModConfigBackups.filesCount), backup.totalFiles)) · \(backup.formattedSize)")
                                .font(AppDesign.Font.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain).focusRing()
                .pointingHandCursor()

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain).focusRing()
                .pointingHandCursor()
                .iconHelp(localization.L(L10n.ModConfigBackups.deleteBackup))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .onHover { isHovered = $0 }

            if isExpanded {
                Divider().padding(.leading, 14)
                VStack(alignment: .leading, spacing: 6) {
                    // Au-dessus de la liste, pas sous ses 200 lignes ; rien
                    // n'est coché d'office (un clic écrasait tout le parc).
                    HStack(spacing: AppDesign.Spacing.sm) {
                        Button(localization.L(L10n.ModConfigBackups.checkAll)) {
                            selectedItemIds = Set(items.filter { $0.configOnly != nil }.map(\.id))
                        }.focusRing(cornerRadius: 5)
                        Button(localization.L(L10n.ModConfigBackups.checkNone)) { selectedItemIds = [] }.focusRing(cornerRadius: 5)
                        Spacer()
                        Button(String(format: localization.L(L10n.ModConfigBackups.restoreCount), selectedItemIds.count),
                               action: onRestoreSelected)
                            .buttonStyle(.borderedProminent).focusRing()
                            .disabled(selectedItemIds.isEmpty)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .padding(.bottom, 4)
                    ForEach(items) { item in
                        Toggle(isOn: Binding(
                            get: { selectedItemIds.contains(item.id) },
                            set: { isOn in
                                if isOn { selectedItemIds.insert(item.id) } else { selectedItemIds.remove(item.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.modDisplayName)
                                    .font(AppDesign.Font.caption(.medium))
                                let subtitle = item.parentFolderName.map {
                                    "\(item.files.joined(separator: ", ")) — \(String(format: localization.L(L10n.ModConfigBackups.partOfGroup), $0))"
                                } ?? item.files.joined(separator: ", ")
                                Text(subtitle)
                                    .font(AppDesign.Font.iconXS)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(item.configOnly == nil)  // traductions seulement : rien à restaurer ici
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .cardSurface(padding: 0)
    }
}
