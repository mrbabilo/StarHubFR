import AppKit
import SwiftUI

/// I-T20 — les gestes de sélection multiple de la liste des mods.
extension ModListState {
    /// Clic sur une ligne de premier niveau : ⌘ ajoute ou retire, ⇧ étend la
    /// plage depuis l'ancre, sinon la ligne seule. Rend le geste lu.
    @MainActor @discardableResult
    func clickRow(_ folderName: String, viewModel: StarHubTHViewModel) -> ModListSelection.ClickKind {
        let flags = NSEvent.modifierFlags
        let kind: ModListSelection.ClickKind = flags.contains(.command) ? .toggle
            : flags.contains(.shift) ? .extend : .plain
        selection.click(folderName, kind: kind, in: displayOrder)
        viewModel.selectedModID = folderName
        return kind
    }

    /// Les mods sélectionnés encore affichés ; à défaut, la ligne courante si
    /// elle l'est — Espace bascule alors ce seul mod (`effectiveMembers`).
    @MainActor
    func selectedMods(_ viewModel: StarHubTHViewModel, order: [String]? = nil) -> [ModItem] {
        let ids = Set(selection.effectiveMembers(in: order ?? displayOrder, current: viewModel.selectedModID))
        return viewModel.mods.filter { ids.contains($0.folderName) }
    }

    /// Bascule la sélection ; `enable` absent, c'est la règle d'Espace.
    @MainActor
    func toggleSelection(_ viewModel: StarHubTHViewModel, enable: Bool? = nil) -> Bool {
        let mods = selectedMods(viewModel)
        guard !mods.isEmpty else { return false }
        viewModel.toggleMods(mods, enable: enable ?? ModListSelection.spaceEnables(mods))
        return true
    }
}

/// Bandeau sous la liste dès deux mods sélectionnés : le compte, les deux
/// gestes et de quoi vider la sélection. Sans lui, Espace serait introuvable.
struct ModListSelectionBar: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @ObservedObject var listState: ModListState
    /// L'ordre affiché, passé par la liste : `displayOrder` n'est écrit
    /// qu'après le rendu et ne redessinerait pas la barre au repli d'un groupe.
    let order: [String]
    @State private var trashPlan: ModTrashSelection.Plan?

    var body: some View {
        let count = listState.selection.members(in: order).count
        if count >= 2 {
            let selected = listState.selectedMods(viewModel, order: order)
            Divider()
            HStack(spacing: AppDesign.Spacing.sm) {
                Text(String(format: localization.L(L10n.Mods.selectionCount), Int64(count)))
                    .font(AppDesign.Font.body.monospacedDigit())
                Spacer()
                // Trois gestes à 560 pt : libellés complets s'ils tiennent,
                // icônes et infobulles sinon (`AdaptiveLabels`, AGENTS §6).
                AdaptiveLabels {
                    HStack(spacing: AppDesign.Spacing.sm) {
                        Button {
                            _ = listState.toggleSelection(viewModel, enable: true)
                        } label: {
                            Label(localization.L(L10n.Mods.selectionEnable), systemImage: "play.circle")
                        }
                        .help(localization.L(L10n.Mods.selectionEnable))
                        Button {
                            _ = listState.toggleSelection(viewModel, enable: false)
                        } label: {
                            Label(localization.L(L10n.Mods.selectionPause), systemImage: "pause.circle")
                        }
                        .help(localization.L(L10n.Mods.selectionPause))
                        Button(role: .destructive) {
                            trashPlan = ModTrashSelection.plan(selected: selected, all: viewModel.mods)
                        } label: {
                            Label(localization.L(L10n.Mods.trashSelection), systemImage: "trash")
                        }
                        // Tout refusé (sonde, mods de SMAPI) : grisé, l'infobulle dit pourquoi.
                        .disabled(!ModTrashSelection.hasTrashable(selected))
                        .help(localization.L(ModTrashSelection.hasTrashable(selected)
                                             ? L10n.Mods.trashSelection : L10n.Mods.trashSelectionAllRefused))
                        ModGroupMoveMenu(folders: selected.map(\.folderName),
                                         viewModel: viewModel, localization: localization, listState: listState)
                    }
                }
                Button {
                    listState.selection.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(localization.L(L10n.Mods.selectionClear))
                .accessibilityLabel(localization.L(L10n.Mods.selectionClear))
            }
            .confirmationDialog(
                localization.plural(L10n.Mods.trashSelectionTitle, trashPlan?.trashable.count ?? 0),
                isPresented: Binding(get: { trashPlan != nil }, set: { if !$0 { trashPlan = nil } }),
                titleVisibility: .visible, presenting: trashPlan
            ) { plan in
                if plan.trashable.isEmpty {
                    Button(localization.L(L10n.Saves.cancel), role: .cancel) {}
                } else {
                    Button(localization.L(L10n.Mods.trashSelection), role: .destructive) {
                        // Refusé (jeu ouvert, mesure) ou rien parti : la
                        // sélection reste, le geste se refait tel quel.
                        if viewModel.trashMods(plan.trashable) { listState.selection.clear() }
                    }
                    Button(localization.L(L10n.Saves.cancel), role: .cancel) {}
                }
            } message: { plan in
                Text(plan.trashable.isEmpty ? localization.L(L10n.Mods.trashSelectionAllRefused)
                                            : ModTrashSelectionConfirm.message(plan, localization))
            }
            .disabled(viewModel.bulkToggleProgress != nil)
            .padding(.horizontal, AppDesign.Spacing.xl)
            .padding(.vertical, AppDesign.Spacing.sm)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

/// A3-T8 — l'approbation Nexus dans la grille et la liste : la carte est un
/// bouton, le geste y passe par le menu contextuel.
extension ModListView {
    @ViewBuilder
    func endorseMenuItem(_ mod: ModItem) -> some View {
        if ModEndorsement.actionableId(mod, viewModel: vm) != nil {
            let endorsed = ModEndorsement.isEndorsed(mod, viewModel: vm)
            Button {
                ModEndorsement.toggle(mod, viewModel: vm, localization: localization, reportRefusal: true)
            } label: {
                Label(localization.L(endorsed ? L10n.Mods.endorseWithdraw : L10n.Mods.endorseAdd),
                      systemImage: endorsed ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
        }
    }

    /// Nombres d'approbations et dates de tout le parc (une fois par jour),
    /// puis tes approbations (une requête, avec clé).
    func loadNexusStats() async {
        NexusModStatsRefresher.refreshIfDue(viewModel: vm)
        if vm.hasNexusApiKey { await vm.endorsementStore.loadIfNeeded { vm.log($0) } }
    }
}
