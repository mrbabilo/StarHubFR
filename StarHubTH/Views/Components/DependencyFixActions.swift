import SwiftUI

/// R9 (audit UX 2026-10-16) — le geste qui satisfait une dépendance requise
/// (`DependencyFix`), posé là où le manque s'affiche : l'encart de la ligne
/// dans la liste et l'onglet Dépendances de la fiche.
///
/// Le libellé **nomme la dépendance** (« Activer Nature.RITS ») : sur la ligne
/// d'un dépendant, un « Activer » nu ferait croire qu'on active la ligne.
/// L'activation passe par les gardes de l'hôte (`compatibilityGate`,
/// `conflictActivationGate`), les mêmes que son interrupteur.
struct DependencyFixActions: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let uniqueId: String
    @Binding var pendingActivation: ModItem?
    @Binding var pendingConflict: ConflictActivation?

    var body: some View {
        let entry = viewModel.dependencyDirectory.entry(for: uniqueId)
        let name = entry?.name ?? uniqueId.smapiModName
        Group {
            switch DependencyFix.action(resolved: viewModel.dependencyIndex.resolve(uniqueId)?.mod,
                                        nexusId: entry?.nexusId,
                                        directDownload: !viewModel.nexusDirectDownloadUnavailable) {
            case .activate(let mod):
                Button(String(format: localization.L(L10n.Mods.depsFixActivate), mod.name)) { activate(mod) }
            case .install(let nexusId):
                Button(String(format: localization.L(L10n.Mods.depsFixInstall), name)) {
                    viewModel.expectAndDownloadNexusMod(nexusId: nexusId, uniqueId: uniqueId)
                }
                .disabled(viewModel.isDownloadingFromNexus)
            case .openPage(let nexusId):
                // Sans Premium : la page, et l'archive reviendra par `nxm://`.
                Button(String(format: localization.L(L10n.Mods.depsFixOpenPage), name)) {
                    viewModel.expectNexusMod(nexusId: nexusId, uniqueIds: [uniqueId])
                    NSWorkspace.shared.open(MissingDependencies.filesPage(nexusId: nexusId))
                }
            case .search:
                searchMenu(name)
            case nil:
                EmptyView()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .lineLimit(1)
        .fixedSize()
        .pointingHandCursor()
    }

    /// Même porte que l'interrupteur : un mod signalé cassé ou en conflit se
    /// confirme avant d'être activé.
    private func activate(_ mod: ModItem) {
        if viewModel.activationWarning(for: mod) != nil {
            pendingActivation = mod
        } else if let other = viewModel.conflictWarning(for: mod) {
            pendingConflict = ConflictActivation(mod: mod, other: other)
        } else {
            viewModel.toggleMod(mod)
        }
    }

    /// Hors du dump Pathoschild : la recherche par nom, ou par auteur.
    private func searchMenu(_ name: String) -> some View {
        let author = uniqueId.smapiAuthor
        return Menu {
            Button {
                NexusWebLinks.openSearch(for: name)
            } label: {
                Label(String(format: localization.L(L10n.Mods.searchNexusByModName), name), systemImage: "magnifyingglass")
            }
            if !author.isEmpty {
                Button {
                    NexusWebLinks.openAuthorSearch(for: author)
                } label: {
                    Label(String(format: localization.L(L10n.Mods.searchNexusByAuthor), author), systemImage: "person")
                }
            }
        } label: {
            Text(String(format: localization.L(L10n.Mods.depsFixSearch), name))
        }
    }
}
