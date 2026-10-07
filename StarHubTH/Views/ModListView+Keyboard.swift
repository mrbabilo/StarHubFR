import SwiftUI

// Les flèches dans la liste des mods (I-T6, constat du 2026-09-25 : Tab
// atteint la liste, mais rien ne la parcourt). La règle vit dans Core
// (`ModListKeyStep`, `ModListSelection`, testées) ; ici, seulement le
// branchement : la touche, la ligne courante (`vm.selectedModID`), la
// sélection multiple (I-T20), la page et le défilement. La liste ne reçoit
// ces touches qu'avec le focus : taper dans la recherche n'en déclenche aucune.
extension ModListView {

    static let navigationKeys: Set<KeyEquivalent> = [.upArrow, .downArrow, .home, .end, .return,
                                                     .space, .escape, "a"]

    /// ↑ ↓ déplacent la sélection dans le cadrage entier (la page suit), ⇧
    /// les étend ; Début / Fin sautent aux bouts, Entrée ouvre la fiche,
    /// Espace bascule la sélection, ⌘A prend tout le cadrage, Échap le vide.
    func handleListKey(_ press: KeyPress, display: [ModItem], page: Int,
                       proxy: ScrollViewProxy) -> KeyPress.Result {
        let order = display.map(\.folderName)
        let move: ModListKeyStep.Move
        switch press.key {
        case .return:
            guard let id = vm.selectedModID,
                  let mod = display.first(where: { $0.folderName == id }) else { return .ignored }
            vm.navigationStore.setViewingModDetail(mod)
            return .handled
        case .space:
            return listState.toggleSelection(vm) ? .handled : .ignored
        case .escape:
            guard !listState.selection.selected.isEmpty || vm.selectedModID != nil else { return .ignored }
            listState.selection.clear()
            vm.selectedModID = nil
            return .handled
        case "a":
            guard press.modifiers.contains(.command) else { return .ignored }
            listState.selection.selectAll(order)
            return .handled
        case .upArrow: move = .previous
        case .downArrow: move = .next
        case .home: move = .first
        case .end: move = .last
        default: return .ignored
        }
        guard let target = ModListKeyStep.target(from: vm.selectedModID, move: move,
                                                 in: order, currentPage: page, pageSize: pageSize)
        else { return .handled }
        vm.selectedModID = target.folderName
        listState.selection.click(target.folderName,
                                  kind: press.modifiers.contains(.shift) ? .extend : .plain, in: order)
        if target.page != page { listState.filters.page = target.page }
        // Après le rendu de la nouvelle page, sinon la ligne n'existe pas encore.
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(target.folderName)
        }
        return .handled
    }
}
