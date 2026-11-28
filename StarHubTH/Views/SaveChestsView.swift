import SwiftUI

/// A2 — les coffres de la partie : la liste par lieu à gauche, le contenu du
/// coffre choisi à droite. Données de `SaveEditSession.chests` (une seule
/// lecture par partie ouverte). A4 : un coffre éditable se modifie comme le sac
/// (quantité, case vidée) et s'enregistre par le bouton du pied, avec le reste.
struct SaveChestsView: View {
    @Bindable var session: SaveEditSession
    @ObservedObject var localization: LocalizationStore
    @State private var query = ""
    @State private var selectedId: String?

    private var labels: SaveChest.Labels {
        SaveChest.Labels(chest: localization.L(L10n.Saves.chestDefault),
                         fridge: localization.L(L10n.Saves.chestFridge),
                         junimo: localization.L(L10n.Saves.chestJunimo))
    }

    var body: some View {
        let groups = SaveChestListing.groups(session.chests, matching: query, name: session.displayName)
        let visibleIds = Set(groups.flatMap(\.chests).map(\.id))
        return VStack(spacing: 0) {
            searchField
            if let problem = session.catalogProblem {
                SaveCatalogProblemLine(problem: problem, localization: localization)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppDesign.Spacing.xl)
                    .padding(.bottom, AppDesign.Spacing.sm)
            }
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

    /// Une case d'un coffre éditable, patron de `SaveEditorInventorySection` : quantité d'un
    /// objet, et case vidée pour tout objet.
    private func editableRow(chest index: Int, slot: Int) -> some View {
        let item = session.chests[index].items[slot]
        return SplitRow(spacing: AppDesign.Spacing.sm) {
            Text(session.displayName(item))
        } trailing: {
            if item.isObject {
                Text(localization.L(L10n.Saves.itemQuantity))
                TextField("", value: $session.chests[index].items[slot].stack, formatter: SlotQuantityFormat.formatter)
                    .frame(width: 60).textFieldStyle(.roundedBorder)
            } else {
                Text(localization.L(L10n.Saves.nonObject)).foregroundColor(.secondary)
            }
            Button(role: .destructive, action: {
                session.chests[index].items[slot] = InventoryItem.empty(slot: slot)
            }) { Image(systemName: "trash").foregroundStyle(AppDesign.Color.error) }
            .buttonStyle(.plain).focusRing()
            .iconHelp(localization.L(L10n.Saves.clearSlotHint))
        }
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
                    Label(localization.L(chest.readOnlyKey), systemImage: "lock")
                        .font(AppDesign.Font.caption).foregroundColor(.secondary)
                }
                Divider()
                if held.isEmpty {
                    Text(localization.L(L10n.Saves.chestAllEmpty)).foregroundColor(.secondary)
                } else if chest.isEditable, let index = session.chests.firstIndex(where: { $0.id == chest.id }) {
                    List(chest.items.indices.filter { !chest.items[$0].name.isEmpty }, id: \.self) { slot in
                        editableRow(chest: index, slot: slot)
                    }
                } else {
                    List(held) { item in
                        SplitRow(spacing: AppDesign.Spacing.sm) {
                            Text(session.displayName(item))
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
