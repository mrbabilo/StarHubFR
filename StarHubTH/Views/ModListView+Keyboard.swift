import SwiftUI

// Les flèches dans la liste des mods (I-T6, constat du 2026-09-25 : Tab
// atteint la liste, mais rien ne la parcourt). La règle vit dans Core
// (`ModListKeyStep`, testée) ; ici, seulement le branchement : la touche,
// la sélection existante (`vm.selectedModID`, déjà teintée par la ligne),
// la page et le défilement.
extension ModListView {

    static let navigationKeys: Set<KeyEquivalent> = [.upArrow, .downArrow, .home, .end, .return]

    /// ↑ ↓ déplacent la sélection dans le cadrage entier (la page suit),
    /// Début / Fin sautent aux bouts, Entrée ouvre la fiche.
    func handleListKey(_ key: KeyEquivalent, display: [ModItem], page: Int,
                       proxy: ScrollViewProxy) -> KeyPress.Result {
        if key == .return {
            guard let id = vm.selectedModID,
                  let mod = display.first(where: { $0.folderName == id }) else { return .ignored }
            vm.navigationStore.setViewingModDetail(mod)
            return .handled
        }
        let move: ModListKeyStep.Move
        switch key {
        case .upArrow: move = .previous
        case .downArrow: move = .next
        case .home: move = .first
        case .end: move = .last
        default: return .ignored
        }
        guard let target = ModListKeyStep.target(from: vm.selectedModID, move: move,
                                                 in: display.map(\.folderName),
                                                 currentPage: page, pageSize: pageSize)
        else { return .handled }
        vm.selectedModID = target.folderName
        if target.page != page { listState.filters.page = target.page }
        // Après le rendu de la nouvelle page, sinon la ligne n'existe pas encore.
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(target.folderName)
        }
        return .handled
    }
}
