import Testing
@testable import StarHubTHCore

@Suite("Flèches dans la liste des mods")
struct ModListKeyStepTests {
    /// 5 mods, pages de 2 : [a b] [c d] [e].
    private let order = ["a", "b", "c", "d", "e"]

    private func step(_ current: String?, _ move: ModListKeyStep.Move, page: Int = 1)
        -> (folderName: String, page: Int)? {
        ModListKeyStep.target(from: current, move: move, in: order, currentPage: page, pageSize: 2)
    }

    @Test func descendreEtMonterDUnCran() {
        #expect(step("b", .next)?.folderName == "c")
        #expect(step("c", .previous)?.folderName == "b")
    }

    @Test func franchirUnBoutDePageChangeDePage() {
        #expect(step("b", .next)?.page == 2)
        #expect(step("c", .previous)?.page == 1)
        #expect(step("d", .next)?.page == 3)
    }

    @Test func auxBoutsRienNeBouge() {
        #expect(step("e", .next) == nil)
        #expect(step("a", .previous) == nil)
    }

    @Test func sansSelectionOnPartDeLaPageAffichee() {
        #expect(step(nil, .next, page: 2)?.folderName == "c")
        #expect(step(nil, .previous, page: 2)?.folderName == "d")
        // Dernière page incomplète : ↑ prend son seul mod.
        #expect(step(nil, .previous, page: 3)?.folderName == "e")
    }

    /// Une sélection sortie du cadrage (filtre posé après coup) vaut
    /// « pas de sélection » : on repart de la page, pas d'un index périmé.
    @Test func uneSelectionHorsCadrageRepartDeLaPage() {
        #expect(step("zz", .next, page: 2)?.folderName == "c")
    }

    @Test func debutEtFin() {
        #expect(step("c", .first).map { [$0.folderName, "\($0.page)"] } == ["a", "1"])
        #expect(step("a", .last).map { [$0.folderName, "\($0.page)"] } == ["e", "3"])
    }

    @Test func listeVide() {
        #expect(ModListKeyStep.target(from: nil, move: .next, in: [], currentPage: 1, pageSize: 12) == nil)
    }
}
