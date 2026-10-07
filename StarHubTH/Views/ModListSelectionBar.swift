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

    /// Les mods sélectionnés encore dans le cadrage ; à défaut, la ligne
    /// courante — Espace bascule alors ce seul mod.
    @MainActor
    func selectedMods(_ viewModel: StarHubTHViewModel) -> [ModItem] {
        var ids = Set(selection.members(in: displayOrder))
        if ids.isEmpty, let current = viewModel.selectedModID { ids = [current] }
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

    var body: some View {
        let count = listState.selection.members(in: listState.displayOrder).count
        if count >= 2 {
            Divider()
            HStack(spacing: AppDesign.Spacing.sm) {
                Text(String(format: localization.L(L10n.Mods.selectionCount), Int64(count)))
                    .font(AppDesign.Font.body.monospacedDigit())
                Spacer()
                Button(localization.L(L10n.Mods.selectionEnable)) {
                    _ = listState.toggleSelection(viewModel, enable: true)
                }
                Button(localization.L(L10n.Mods.selectionPause)) {
                    _ = listState.toggleSelection(viewModel, enable: false)
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
            .disabled(viewModel.bulkToggleProgress != nil)
            .padding(.horizontal, AppDesign.Spacing.xl)
            .padding(.vertical, AppDesign.Spacing.sm)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}
