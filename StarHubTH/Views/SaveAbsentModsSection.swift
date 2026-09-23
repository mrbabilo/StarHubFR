import SwiftUI

/// A1-T9 — la section de la fiche de sauvegarde qui dit quels mods
/// **disparus de la médiathèque** y ont laissé des clés SMAPI. Lecture
/// seule : une rangée par mod, sans fiche à ouvrir — le mod n'existe plus
/// dans le parc. Le texte suit la sévérité mesurée : ce contenu dort, il
/// n'est pas cassé (réinstaller le mod le récupère).
struct SaveAbsentModsSection: View {
    let vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let save: SaveGameInfo

    @State private var store = SaveAbsentModsStore()

    /// Ce qui périme le résultat : une autre save, une save réécrite, ou le
    /// parc lui-même — un mod réinstallé ou retiré change la liste.
    private struct RefreshKey: Hashable {
        let folderName: String
        let modified: Date
        let ids: Set<String>
        let parcLoading: Bool
    }

    private var refreshKey: RefreshKey {
        let parc = vm.scanStore
        return RefreshKey(
            folderName: save.folderName,
            modified: save.lastModified,
            ids: parc.mods.allUniqueIds,
            parcLoading: parc.mods.isEmpty && parc.scanProgress != nil)
    }

    var body: some View {
        Section {
            switch store.state {
            case .idle, .scanning:
                HStack(spacing: AppDesign.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(localization.L(L10n.Saves.absentModsScanning))
                        .foregroundStyle(.secondary)
                }
            case .unreadable:
                Text(localization.L(L10n.Saves.absentModsUnreadable))
                    .foregroundStyle(.secondary)
            case .loaded(let entries) where entries.isEmpty:
                Text(localization.L(L10n.Saves.absentModsNone))
                    .foregroundStyle(.secondary)
            case .loaded(let entries):
                ForEach(entries, id: \.uid) { entry in
                    row(entry)
                }
            }
        } header: {
            Text(localization.L(L10n.Saves.absentModsTitle))
        } footer: {
            if case .loaded(let entries) = store.state, !entries.isEmpty {
                Text(localization.L(L10n.Saves.absentModsFooter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: refreshKey) {
            // Parc vide pendant son premier scan : « aucun mod disparu »
            // serait un faux « tout va bien » — rester en lecture, la clé
            // change quand le parc arrive.
            guard !refreshKey.parcLoading else { return }
            store.refresh(save: save, mods: vm.scanStore.mods)
        }
    }

    private func row(_ entry: AbsentModFootprint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.uid)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(String(format: localization.L(L10n.Saves.absentModsKeys), entry.keys))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
