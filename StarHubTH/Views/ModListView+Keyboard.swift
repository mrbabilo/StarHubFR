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
    /// `groupedPages` (I-T21) : en mode groupé, la page d'un mod se lit dans
    /// le découpage en sections, pas par `index / pageSize`.
    func handleListKey(_ press: KeyPress, display: [ModItem], groupedPages: [[ModListPageSection]], page: Int,
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
        // En mode groupé, la page affichée commence après les mods des pages
        // d'avant, pas à `(page - 1) × pageSize`.
        var bounds: ClosedRange<Int>?
        if groupedPages.indices.contains(page - 1) {
            let start = ModGroupPages.modsBefore(page: page, in: groupedPages)
            let shown = groupedPages[page - 1].reduce(0) { $0 + $1.mods.count }
            bounds = start...(start + max(shown, 1) - 1)
        }
        guard let target = ModListKeyStep.target(from: vm.selectedModID, move: move,
                                                 in: order, currentPage: page, pageSize: pageSize,
                                                 pageBounds: bounds)
        else { return .handled }
        vm.selectedModID = target.folderName
        listState.selection.click(target.folderName,
                                  kind: press.modifiers.contains(.shift) ? .extend : .plain, in: order)
        let targetPage = groupedPages.isEmpty ? target.page
            : (ModGroupPages.page(of: target.folderName, in: groupedPages) ?? target.page)
        if targetPage != page { listState.filters.page = targetPage }
        // Après le rendu de la nouvelle page, sinon la ligne n'existe pas encore.
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(target.folderName)
        }
        return .handled
    }
}
