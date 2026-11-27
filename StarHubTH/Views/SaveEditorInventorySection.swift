import SwiftUI

/// Le sac du fermier dans l'éditeur. Pas de bouton à lui : il s'enregistre
/// avec la fiche, par le bouton du pied (audit UX 2026-11-27, F1).
struct SaveEditorInventorySection: View {
    @Bindable var session: SaveEditSession
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        Section(localization.L(L10n.Saves.inventoryEditor)) {
            ForEach(session.inventory.indices, id: \.self) { index in
                let item = session.inventory[index]
                if item.isObject {
                    SplitRow(spacing: AppDesign.Spacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text("\(localization.L(L10n.Saves.itemId)): \(item.itemId)")
                                .font(AppDesign.Font.caption).foregroundColor(.secondary)
                        }
                    } trailing: {
                        Text(localization.L(L10n.Saves.itemQuantity))
                        TextField("", value: $session.inventory[index].stack,
                                  formatter: NumberFormatter())
                            .frame(width: 60).textFieldStyle(.roundedBorder)
                        Button(role: .destructive, action: {
                            session.inventory[index] = InventoryItem.empty(slot: index)
                        }) { Image(systemName: "trash").foregroundStyle(AppDesign.Color.error) }
                        .buttonStyle(.plain).focusRing()
                        .iconHelp(localization.L(L10n.Saves.clearSlotHint))
                    }
                } else if !item.name.isEmpty {
                    SplitRow(spacing: AppDesign.Spacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            if !item.itemId.isEmpty {
                                Text("\(localization.L(L10n.Saves.itemId)): \(item.itemId)")
                                    .font(AppDesign.Font.caption).foregroundColor(.secondary)
                            }
                        }
                    } trailing: {
                        Text(localization.L(L10n.Saves.nonObject)).foregroundColor(.secondary)
                        Button(role: .destructive, action: {
                            session.inventory[index] = InventoryItem.empty(slot: index)
                        }) { Image(systemName: "trash").foregroundStyle(AppDesign.Color.error) }
                        .buttonStyle(.plain).focusRing()
                        .iconHelp(localization.L(L10n.Saves.clearSlotHint))
                    }
                }
            }
        }
    }
}
