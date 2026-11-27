import SwiftUI

/// A2 — les coffres de la partie, en lecture : la liste par lieu à gauche, le
/// contenu du coffre choisi à droite. Données de `SaveEditSession.chests` (une
/// seule lecture par partie ouverte) ; aucune écriture avant A4.
struct SaveChestsView: View {
    let session: SaveEditSession
    @ObservedObject var localization: LocalizationStore
    @State private var query = ""
    @State private var selectedId: String?

    private var labels: SaveChest.Labels {
        SaveChest.Labels(chest: localization.L(L10n.Saves.chestDefault),
                         fridge: localization.L(L10n.Saves.chestFridge),
                         junimo: localization.L(L10n.Saves.chestJunimo))
    }

    var body: some View {
        let groups = SaveChestListing.groups(session.chests, matching: query)
        let visibleIds = Set(groups.flatMap(\.chests).map(\.id))
        return VStack(spacing: 0) {
            searchField
            Divider()
            if groups.isEmpty {
                Text(localization.L(session.chests.isEmpty ? L10n.Saves.chestsEmpty : L10n.Saves.chestsNoMatch))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    List(selection: $selectedId) {
                        ForEach(groups) { group in
                            Section(group.location.isEmpty ? localization.L(L10n.Saves.chestsShared) : group.location) {
                                ForEach(group.chests) { chest in row(chest).tag(chest.id) }
                            }
                        }
                    }
                    .frame(width: 280)
                    Divider()
                    detail(groups.flatMap(\.chests).first { $0.id == selectedId })
                }
            }
        }
        // Une recherche qui masque le coffre choisi lâche aussi la sélection.
        .onChange(of: visibleIds) { _, ids in
            if let id = selectedId, !ids.contains(id) { selectedId = nil }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(AppDesign.Font.caption)
            TextField(localization.L(L10n.Saves.chestsSearch), text: $query)
                .textFieldStyle(.plain).font(AppDesign.Font.caption)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain).focusRing().iconHelp(localization.L(L10n.Discovery.clearSearch))
            }
        }
        .padding(.horizontal, AppDesign.Spacing.xl)
        .padding(.vertical, AppDesign.Spacing.sm)
    }

    private func row(_ chest: SaveChest) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chest.displayName(labels)).lineLimit(1)
            Text(String(format: localization.L(L10n.Saves.chestSlots), chest.slotCount, chest.occupiedCount))
                .font(AppDesign.Font.caption).foregroundColor(.secondary)
        }
    }

    private func readOnlyKey(_ chest: SaveChest) -> String {
        if case .modInventory = chest.kind { return L10n.Saves.chestReadOnly }
        return L10n.Saves.chestNotEditable
    }

    @ViewBuilder
    private func detail(_ chest: SaveChest?) -> some View {
        if let chest {
            let held = chest.items.filter { !$0.name.isEmpty }
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                Text(chest.displayName(labels)).font(.headline)
                Text(String(format: localization.L(L10n.Saves.chestSlots), chest.slotCount, chest.occupiedCount))
                    .font(AppDesign.Font.caption).foregroundColor(.secondary)
                if !chest.isEditable {
                    Label(localization.L(readOnlyKey(chest)), systemImage: "lock")
                        .font(AppDesign.Font.caption).foregroundColor(.secondary)
                }
                Divider()
                if held.isEmpty {
                    Text(localization.L(L10n.Saves.chestAllEmpty)).foregroundColor(.secondary)
                } else {
                    List(held) { item in
                        SplitRow(spacing: AppDesign.Spacing.sm) {
                            Text(item.name)
                        } trailing: {
                            if item.isObject { Text("× \(item.stack)").foregroundColor(.secondary) }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(AppDesign.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text(localization.L(L10n.Saves.chestPick)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
