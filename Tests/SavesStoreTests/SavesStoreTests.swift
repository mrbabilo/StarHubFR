import Testing
import Foundation
@testable import StarHubTHCore

/// Le store du domaine Sauvegardes : l'état affiché et le verrou d'écriture.
/// La filiation et le tri sont prouvés ailleurs (`SaveTreeTests`) — ici, c'est
/// la **composition** : tri + filtre par étiquette + tags disponibles.
///
/// Les étiquettes arrivent par closure (aucun test n'écrit dans le vrai
/// domaine de préférences — CLAUDE.md).
@Suite struct SavesStoreTests {

    private func save(_ folder: String, player: String = "P", money: Int = 0,
                      modified: TimeInterval = 0) -> SaveGameInfo {
        SaveGameInfo(folderName: folder, fileURL: URL(fileURLWithPath: "/tmp/\(folder)"),
                     lastModified: Date(timeIntervalSince1970: modified),
                     playerName: player, farmName: "F", favoriteThing: "", money: money,
                     spouse: "", maxHealth: 0, maxStamina: 0, goldenWalnuts: 0, qiGems: 0,
                     clubCoins: 0, totalMoneyEarned: 0, year: 1, season: 0, day: 1, whichFarm: 0)
    }

    private func store(tags: [String: String] = [:]) -> SavesStore {
        SavesStore(tagForSave: { tags[$0] ?? "" })
    }

    // MARK: - Hiérarchie

    @Test func hierarchyIsEmptyUntilSavesArrive() {
        #expect(store().hierarchy.isEmpty)
    }

    @Test func hierarchyNestsChildrenUnderTheFolderTheyExtend() {
        let s = store()
        s.replace(saves: [save("Farm_1"), save("Farm_1_2")])
        #expect(s.hierarchy.count == 1)
        #expect(s.hierarchy.first?.children.map(\.info.folderName) == ["Farm_1_2"])
    }

    @Test func theSortOptionDecidesTheOrderOfTheRoots() {
        let s = store()
        // `.name` trie sur `playerName`, pas sur le nom de dossier — d'où
        // deux fermiers distincts, sans quoi le tri n'aurait rien à départager.
        s.replace(saves: [save("Rich", player: "Zoe", money: 900),
                          save("Poor", player: "Anna", money: 1)])
        s.sortOption = .money
        #expect(s.hierarchy.map(\.info.folderName) == ["Rich", "Poor"])
        s.sortOption = .name
        #expect(s.hierarchy.map(\.info.folderName) == ["Poor", "Rich"])
    }

    // MARK: - Filtre par étiquette

    @Test func anEmptyFilterKeepsEveryRoot() {
        let s = store(tags: ["A": "été"])
        s.replace(saves: [save("A"), save("B")])
        #expect(s.hierarchy.count == 2)
    }

    @Test func theFilterKeepsOnlyTheRootsCarryingThatTag() {
        let s = store(tags: ["A": "été", "B": "hiver"])
        s.replace(saves: [save("A"), save("B")])
        s.filterTag = "hiver"
        #expect(s.hierarchy.map(\.info.folderName) == ["B"])
    }

    @Test func theFilterJudgesTheRootOnly_aTaggedChildDoesNotSaveItsParent() {
        // Comportement historique, préservé à l'extraction : le filtre
        // s'applique aux racines, et un enfant étiqueté ne remonte pas.
        let s = store(tags: ["Farm_1_2": "hiver"])
        s.replace(saves: [save("Farm_1"), save("Farm_1_2")])
        s.filterTag = "hiver"
        #expect(s.hierarchy.isEmpty)
    }

    // MARK: - Étiquettes disponibles

    @Test func availableTagsAreTheDistinctNonEmptyOnes_sorted() {
        let s = store(tags: ["A": "été", "B": "été", "C": "hiver", "D": ""])
        s.replace(saves: [save("A"), save("B"), save("C"), save("D")])
        #expect(s.availableFilterTags == ["hiver", "été"])
    }

    @Test func availableTagsCountChildrenToo_notJustRoots() {
        // `availableFilterTags` parcourt `saves`, pas l'arbre : une étiquette
        // posée sur un enfant reste proposable même si le filtre l'ignore.
        let s = store(tags: ["Farm_1_2": "hiver"])
        s.replace(saves: [save("Farm_1"), save("Farm_1_2")])
        #expect(s.availableFilterTags == ["hiver"])
    }

    // MARK: - Verrou

    @Test func theFirstOperationTakesTheLock() {
        let s = store()
        #expect(s.beginOperation() == true)
        #expect(s.isOperationRunning)
    }

    @Test func aSecondOperationIsRefusedWhileTheFirstRuns() {
        let s = store()
        _ = s.beginOperation()
        #expect(s.beginOperation() == false)
        // Et le refus ne relâche rien : la première tourne toujours.
        #expect(s.isOperationRunning)
    }

    @Test func theLockIsFreeAgainAfterTheOperationEnds() {
        let s = store()
        _ = s.beginOperation()
        s.endOperation()
        #expect(s.isOperationRunning == false)
        #expect(s.beginOperation() == true)
    }
}
