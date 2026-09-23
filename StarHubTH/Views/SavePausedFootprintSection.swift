import SwiftUI

/// A1-T6 — la section de la fiche de sauvegarde qui dit quels mods **en
/// pause** y ont laissé du contenu. Chaque rangée conduit à la fiche du mod
/// (un écran de diagnostic doit conduire). Lecture seule, et le texte suit
/// la sévérité mesurée : ce contenu dort, il n'est pas perdu (A1-T6).
struct SavePausedFootprintSection: View {
    @Bindable var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let save: SaveGameInfo
    @Binding var currentTab: SidebarDestination

    @State private var store = SavePausedFootprintStore()

    /// Ce qui périme le résultat : une autre save, une save réécrite, ou un
    /// mod qui change d'état dans le parc (une bascule).
    private struct RefreshKey: Hashable {
        let folderName: String
        let modified: Date
        let paused: [String]
    }

    private var refreshKey: RefreshKey {
        RefreshKey(
            folderName: save.folderName,
            modified: save.lastModified,
            paused: vm.scanStore.mods.flattenedMods.filter { !$0.isEnabled }.map(\.folderName))
    }

    var body: some View {
        Section {
            switch store.state {
            case .idle, .scanning:
                HStack(spacing: AppDesign.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(localization.L(L10n.Saves.pausedFootprintsScanning))
                        .foregroundStyle(.secondary)
                }
            case .unreadable:
                Text(localization.L(L10n.Saves.pausedFootprintsUnreadable))
                    .foregroundStyle(.secondary)
            case .loaded(let entries) where entries.isEmpty:
                Text(localization.L(L10n.Saves.pausedFootprintsNone))
                    .foregroundStyle(.secondary)
            case .loaded(let entries):
                ForEach(entries, id: \.folderName) { entry in
                    row(entry)
                }
            }
        } header: {
            Text(localization.L(L10n.Saves.pausedFootprintsTitle))
        } footer: {
            if case .loaded(let entries) = store.state, !entries.isEmpty {
                Text(localization.L(L10n.Saves.pausedFootprintsFooter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: refreshKey) {
            store.refresh(save: save, mods: vm.scanStore.mods)
        }
    }

    private func row(_ entry: PausedModFootprint) -> some View {
        Button {
            open(entry)
        } label: {
            HStack(spacing: AppDesign.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(FingerprintSummary.families(entry.counts, localization: localization))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: AppDesign.Spacing.sm)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(localization.L(L10n.Saves.pausedFootprintsOpenHint))
    }

    /// Poser la cible **puis** changer d'onglet — jamais l'inverse :
    /// `MainView` remet les vues de détail à nil au changement d'onglet, et
    /// `pendingModDetailFocus` traverse ce changement (patron de
    /// `SystemAlertsView`). La fiche s'ouvre sur « État » : c'est là qu'on
    /// réactive le mod.
    private func open(_ entry: PausedModFootprint) {
        vm.navigationStore.pendingModDetailFocus = entry.folderName
        vm.navigationStore.pendingDetailTab = .state
        currentTab = .mods
    }
}
