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
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.trashEvents.isEmpty {
                HStack {
                    Text(localization.L(L10n.Maintenance.trashSectionTitle))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(localization.L(L10n.Maintenance.trashPurgeAll)) {
                        onPurgeAll(viewModel.trashEvents.count)
                    }
                    .controlSize(.small)
                    .foregroundColor(.red)
                }
                ForEach(viewModel.trashEvents) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.secondary)
                            Text(event.date.map {
                                $0.formatted(date: .abbreviated, time: .shortened)
                            } ?? event.folderName)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            if event.entries.count > 1 {
                                Button(String(format: localization.L(L10n.Maintenance.trashRestoreEvent),
                                              Int64(event.entries.count))) {
                                    viewModel.restoreTrashEvent(event.folderName)
                                }
                                .controlSize(.small)
                            }
                        }
                        // Un vidage des mods en pause pose ~720 entrées dans un
                        // seul événement : la liste se replie, sinon l'écran
                        // construirait toutes ses lignes d'un coup.
                        let expanded = expandedTrashEvents.contains(event.folderName)
                        let shown = expanded ? event.entries
                            : Array(event.entries.prefix(Self.trashPreviewCount))
                        ForEach(shown, id: \.self) { entry in
                            HStack {
                                Text(entry)
                                    .font(.system(size: 12, design: .monospaced))
                                Spacer()
                                Button(localization.L(L10n.Maintenance.trashRestore)) {
                                    viewModel.restoreTrashEntry(event: event.folderName, entry: entry)
                                }
                                .controlSize(.small)
                                Button(localization.L(L10n.Maintenance.trashPurgeOne)) {
                                    onPurgeEntry(event.folderName, entry)
                                }
                                .controlSize(.small)
                                .foregroundColor(.red)
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
                            .buttonStyle(.link)
                            .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                Text(localization.L(L10n.Maintenance.trashHint2))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
