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
    /// E7 — « À régler » de l'onglet Dépendances : bouton plein. Le menu de
    /// recherche reste en `.bordered`, ce n'est pas un geste qui règle.
    var prominent = false

    var body: some View {
        let entry = viewModel.dependencyDirectory.entry(for: uniqueId)
        let name = entry?.name ?? uniqueId.smapiModName
        Group {
            switch DependencyFix.action(resolved: viewModel.dependencyIndex.resolve(uniqueId)?.mod,
                                        nexusId: entry?.nexusId,
                                        directDownload: !viewModel.nexusDirectDownloadUnavailable) {
            case .activate(let mod):
                Button(String(format: localization.L(L10n.Mods.depsFixActivate), mod.name)) { activate(mod) }
                    .modifier(FixEmphasis(prominent: prominent)).focusRing(cornerRadius: 5)
            case .install(let nexusId):
                Button(String(format: localization.L(L10n.Mods.depsFixInstall), name)) {
                    viewModel.expectAndDownloadNexusMod(nexusId: nexusId, uniqueId: uniqueId)
                }
                .disabled(viewModel.isDownloadingFromNexus).modifier(FixEmphasis(prominent: prominent)).focusRing(cornerRadius: 5)
            case .openPage(let nexusId):
                // Sans Premium : la page, et l'archive reviendra par `nxm://`.
                Button(String(format: localization.L(L10n.Mods.depsFixOpenPage), name)) {
                    viewModel.expectNexusMod(nexusId: nexusId, uniqueIds: [uniqueId])
                    NSWorkspace.shared.open(MissingDependencies.filesPage(nexusId: nexusId))
                }.modifier(FixEmphasis(prominent: prominent)).focusRing(cornerRadius: 5)
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
        }.focusRing(cornerRadius: 5)
    }
}

/// Le style plein, posé sur le bouton lui-même : il l'emporte sur le
/// `.bordered` de l'ensemble (deux styles ne se choisissent pas en ternaire).
private struct FixEmphasis: ViewModifier {
    let prominent: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if prominent { content.buttonStyle(.borderedProminent) } else { content }
    }
}
