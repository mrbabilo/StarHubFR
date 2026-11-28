import SwiftUI

/// Le format des quantités du sac et des coffres : entier, au moins 1 (l'écriture borne aussi).
/// Créé une fois, pas à chaque rendu.
enum SlotQuantityFormat {
    @MainActor static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimum = 1
        formatter.allowsFloats = false
        return formatter
    }()
}

/// Le sac du fermier dans l'éditeur. Pas de bouton à lui : il s'enregistre
/// avec la fiche, par le bouton du pied (audit UX 2026-11-27, F1).
struct SaveEditorInventorySection: View {
    @Bindable var session: SaveEditSession
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        Section(localization.L(L10n.Saves.inventoryEditor)) {
            if let problem = session.catalogProblem {
                SaveCatalogProblemLine(problem: problem, localization: localization)
            }
            ForEach(session.inventory.indices, id: \.self) { index in
                let item = session.inventory[index]
                if item.isObject {
                    SplitRow(spacing: AppDesign.Spacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.displayName(item))
                            Text("\(localization.L(L10n.Saves.itemId)): \(item.itemId)")
                                .font(AppDesign.Font.caption).foregroundColor(.secondary)
                        }
                    } trailing: {
                        Text(localization.L(L10n.Saves.itemQuantity))
                        TextField("", value: $session.inventory[index].stack,
                                  formatter: SlotQuantityFormat.formatter)
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
                            Text(session.displayName(item))
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

/// B4 — pourquoi les noms du jeu manquent, en une ligne, au-dessus du sac et des coffres.
struct SaveCatalogProblemLine: View {
    let problem: CatalogProblem
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(AppDesign.Font.caption).foregroundColor(.secondary)
    }

    private var text: String {
        switch problem {
        case .gameNotFound: localization.L(L10n.Saves.catalogGameNotFound)
        case .unreadable(let file): String(format: localization.L(L10n.Saves.catalogUnreadable), file)
        }
    }
}
