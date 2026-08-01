import Testing
import Foundation
@testable import StarHubTHCore

/// Stardew ne consigne aucun lien de parenté entre sauvegardes : la filiation
/// se déduit du seul nom de dossier. Cette règle décide de la forme de l'arbre
/// affiché, et rien ne la vérifiait.
struct SaveTreeTests {
    private func save(_ folder: String, player: String = "P",
                      money: Int = 0, modified: TimeInterval = 0) -> SaveGameInfo {
        SaveGameInfo(folderName: folder, fileURL: URL(fileURLWithPath: "/tmp/\(folder)"),
                     lastModified: Date(timeIntervalSince1970: modified),
                     playerName: player, farmName: "F", favoriteThing: "", money: money,
                     spouse: "", maxHealth: 0, maxStamina: 0, goldenWalnuts: 0, qiGems: 0,
                     clubCoins: 0, totalMoneyEarned: 0, year: 1, season: 0, day: 1, whichFarm: 0)
    }

    // MARK: - Filiation

    @Test func aSuffixedFolderDescendsFromTheOneItExtends() {
        #expect(SaveTree.parentFolderName(of: "Farm_1_2", among: ["Farm_1", "Farm_1_2"]) == "Farm_1")
    }

    @Test func aFolderWithNoExistingAncestorIsARoot() {
        // « Farm_1 » a bien un `_`, mais aucun « Farm » n'existe : c'est une racine.
        #expect(SaveTree.parentFolderName(of: "Farm_1", among: ["Farm_1"]) == nil)
    }

    @Test func theSearchClimbsPastSegmentsThatMatchNothing() {
        // Un nom de ferme peut contenir des `_` : s'arrêter au premier découpage
        // inventerait un parent inexistant.
        let existing: Set<String> = ["Ma_Ferme_1", "Ma_Ferme_1_a_b"]
        #expect(SaveTree.parentFolderName(of: "Ma_Ferme_1_a_b", among: existing) == "Ma_Ferme_1")
    }

    @Test func aDeletedParentBreaksTheChainUpwards() {
        // « Farm_1 » a été supprimée : « Farm_1_2 » se rattache à « Farm » s'il existe.
        #expect(SaveTree.parentFolderName(of: "Farm_1_2", among: ["Farm", "Farm_1_2"]) == "Farm")
    }

    @Test func aFolderWithNoSeparatorIsARoot() {
        #expect(SaveTree.parentFolderName(of: "Farm", among: ["Farm"]) == nil)
    }

    // MARK: - Arbre

    @Test func childrenHangUnderTheirParentAndNotAtTheRoot() {
        let tree = SaveTree.build(from: [save("Farm_1"), save("Farm_1_2")], sortedBy: .name)
        #expect(tree.count == 1)
        #expect(tree[0].info.folderName == "Farm_1")
        #expect(tree[0].children.map(\.info.folderName) == ["Farm_1_2"])
    }

    @Test func unrelatedSavesStayAtTheRoot() {
        let tree = SaveTree.build(from: [save("Alpha"), save("Beta")], sortedBy: .name)
        #expect(tree.count == 2)
    }

    @Test func grandchildrenNestTwoLevelsDeep() {
        let tree = SaveTree.build(from: [save("F_1"), save("F_1_2"), save("F_1_2_3")],
                                  sortedBy: .name)
        #expect(tree.count == 1)
        #expect(tree[0].children.first?.children.map(\.info.folderName) == ["F_1_2_3"])
    }

    // MARK: - Tri

    @Test func sortingByNameIsCaseInsensitive() {
        let tree = SaveTree.build(from: [save("b", player: "béatrice"), save("a", player: "Alain")],
                                  sortedBy: .name)
        #expect(tree.map(\.info.playerName) == ["Alain", "béatrice"])
    }

    @Test func sortingByLastPlayedPutsTheMostRecentFirst() {
        let tree = SaveTree.build(from: [save("a", modified: 10), save("b", modified: 900)],
                                  sortedBy: .lastPlayed)
        #expect(tree.map(\.info.folderName) == ["b", "a"])
    }

    @Test func sortingByMoneyPutsTheRichestFirst() {
        let tree = SaveTree.build(from: [save("a", money: 5), save("b", money: 5000)],
                                  sortedBy: .money)
        #expect(tree.map(\.info.folderName) == ["b", "a"])
    }

    @Test func childrenAreSortedToo() {
        let saves = [save("F"), save("F_1", money: 1), save("F_2", money: 99)]
        let tree = SaveTree.build(from: saves, sortedBy: .money)
        #expect(tree[0].children.map(\.info.folderName) == ["F_2", "F_1"])
    }

    @Test func noSavesYieldNoTree() {
        #expect(SaveTree.build(from: [], sortedBy: .name).isEmpty)
    }
}
