import SwiftUI

/// A5-T6 — avant d'installer une mise à jour : les mods **actifs** qui
/// cherchent par leur nom des types internes du mod remplacé (choix du
/// 2026-10-08 : les mods en pause ne perdent rien tant qu'ils dorment).
/// Déclarée ou non, une dépendance ne protège pas d'un type renommé : tous
/// les liens comptent ici. Un citant livré dans la même archive est mis à
/// jour avec sa cible, il n'est pas cité.
struct HiddenCodeUpdateWarning: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let detectedMods: [DetectedMod]

    private struct Readers: Identifiable {
        let id: String
        let targetName: String
        let readerNames: [String]
    }

    private var readers: [Readers] {
        let mods = viewModel.scanStore.mods
        let active = Set(mods.enabledUniqueIds.map { $0.lowercased() })
        let shipped = Set(detectedMods.map { $0.manifest.uniqueId.lowercased() })
        return detectedMods.compactMap { detected in
            let id = detected.manifest.uniqueId
            guard !id.isEmpty, let installed = mods.mod(withUniqueId: id) else { return nil }
            let names = viewModel.hiddenCodeIndex.links(targeting: id)
                .map(\.citing)
                .filter { active.contains($0.lowercased()) && !shipped.contains($0.lowercased()) }
                .map { mods.mod(withUniqueId: $0)?.name ?? $0 }
            guard !names.isEmpty else { return nil }
            return Readers(id: id.lowercased(), targetName: installed.name,
                           readerNames: Array(Set(names)).sorted())
        }
    }

    var body: some View {
        let readers = self.readers
        if !readers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(localization.L(L10n.HiddenCode.updateTitle), systemImage: "doc.text.magnifyingglass")
                    .font(AppDesign.Font.rowTitle(.semibold))
                    .foregroundColor(.orange)
                ForEach(readers) { entry in
                    Text(String(format: localization.L(L10n.HiddenCode.updateLine),
                                entry.targetName, entry.readerNames.joined(separator: ", ")))
                        .font(AppDesign.Font.caption(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(localization.L(L10n.HiddenCode.updateExplain))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12))
            .cornerRadius(8)
        }
    }
}
