import SwiftUI

/// X103-B — la corbeille des mods supprimés : remettre (désactivé) ou
/// purger pour de bon. Rien ne part sans confirmation ; rien ne part non
/// plus sans geste — aucune purge automatique (leçon X25). Les deux purges
/// remontent à `MaintenanceView`, qui porte la feuille de confirmation.
struct MaintenanceTrashSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let onPurgeAll: (Int) -> Void
    let onPurgeEntry: (_ event: String, _ entry: String) -> Void

    /// Les événements dépliés au-delà de l'aperçu.
    @State private var expandedTrashEvents: Set<String> = []
    private static let trashPreviewCount = 8

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            if !viewModel.trashEvents.isEmpty {
                SplitRow(spacing: AppDesign.Spacing.sm) {
                    Text(localization.L(L10n.Maintenance.trashSectionTitle))
                        .font(AppDesign.Font.body(.semibold))
                } trailing: {
                    let title = localization.L(L10n.Maintenance.trashPurgeAll)
                    AdaptiveLabels { Button(role: .destructive) {
                        onPurgeAll(viewModel.trashEvents.count)
                    } label: { Label(title, systemImage: "trash") }
                    .controlSize(.small).foregroundColor(AppDesign.Color.error).help(title) }
                }
                ForEach(viewModel.trashEvents) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        SplitRow(spacing: AppDesign.Spacing.sm) {
                            Image(systemName: "trash")
                                .foregroundColor(.secondary)
                            Text(event.date.map {
                                $0.formatted(date: .abbreviated, time: .shortened)
                            } ?? event.folderName)
                                .font(AppDesign.Font.caption)
                                .foregroundColor(.secondary)
                        } trailing: {
                            if event.entries.count > 1 {
                                let title = String(format: localization.L(L10n.Maintenance.trashRestoreEvent),
                                                   Int64(event.entries.count))
                                AdaptiveLabels { Button {
                                    viewModel.restoreTrashEvent(event.folderName)
                                } label: { Label(title, systemImage: "arrow.uturn.backward") }
                                .controlSize(.small).help(title) }
                            }
                        }
                        // Un vidage des mods en pause pose ~720 entrées dans un
                        // seul événement : la liste se replie, sinon l'écran
                        // construirait toutes ses lignes d'un coup.
                        let expanded = expandedTrashEvents.contains(event.folderName)
                        let shown = expanded ? event.entries
                            : Array(event.entries.prefix(Self.trashPreviewCount))
                        ForEach(shown, id: \.self) { entry in
                            SplitRow(spacing: AppDesign.Spacing.sm) {
                                Text(entry)
                                    .font(AppDesign.Font.monoCaption)
                                    .fixedSize(horizontal: false, vertical: true)
                            } trailing: {
                                AdaptiveLabels { HStack(spacing: AppDesign.Spacing.sm) {
                                    let restore = localization.L(L10n.Maintenance.trashRestore)
                                    Button {
                                        viewModel.restoreTrashEntry(event: event.folderName, entry: entry)
                                    } label: { Label(restore, systemImage: "arrow.uturn.backward") }
                                    .controlSize(.small).help(restore)
                                    let purge = localization.L(L10n.Maintenance.trashPurgeOne)
                                    Button(role: .destructive) {
                                        onPurgeEntry(event.folderName, entry)
                                    } label: { Label(purge, systemImage: "trash") }
                                    .controlSize(.small).foregroundColor(AppDesign.Color.error).help(purge)
                                } }
                            }
                        }
                        if event.entries.count > Self.trashPreviewCount {
                            Button(expanded
                                   ? localization.L(L10n.Maintenance.trashShowLess)
                                   : String(format: localization.L(L10n.Maintenance.trashShowMore),
                                            Int64(event.entries.count - Self.trashPreviewCount))) {
                                if expanded {
                                    expandedTrashEvents.remove(event.folderName)
                                } else {
                                    expandedTrashEvents.insert(event.folderName)
                                }
                            }
                            .buttonStyle(.link).focusRing(cornerRadius: 4)
                            .controlSize(.small)
                        }
                    }
                    .padding(AppDesign.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(AppDesign.Opacity.subtle),
                                in: RoundedRectangle(cornerRadius: AppDesign.Radius.md))
                }
                Text(localization.L(L10n.Maintenance.trashHint2))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
