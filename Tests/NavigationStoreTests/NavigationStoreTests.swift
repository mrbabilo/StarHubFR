import Testing
import Foundation
@testable import StarHubTHCore

/// L'état de **navigation** (chantier « vider le VM de son état publié »,
/// cadrage P8) : les poses inertes se relisent telles quelles, et les deux
/// canaux (`reportDetailFocus`, `pendingTabRequest`) suivent leur cycle de
/// vie posé-par-verbe, consommé-par-verbe — le quitus doit retomber.
///
/// La règle du changement d'onglet vit dans `TabChangePlan` (déjà testée) ;
/// ce qui se prouve ici, c'est le store comme détenteur : une consommation
/// qui n'efface pas, ou un canal qui atterrit sur la mauvaise propriété,
/// ferait survivre une demande d'ouverture jusqu'à la prochaine fiche
/// ouverte à la main — le défaut exact que les pendings existent pour
/// éviter.
@Suite struct NavigationStoreTests {

    // MARK: - Poses inertes : ce qui est posé se relit.

    @Test func poseEtRelitLesPendings() {
        let s = NavigationStore()
        s.pendingModFocus = "X"
        s.pendingTranslationFocus = "Y"
        s.pendingConfigFocus = "Z"
        s.pendingModDetailFocus = "W"
        s.pendingDetailTab = .translation
        s.pendingTranslationDiffFilter = .state(.missing)
        s.pendingLogFocus = "erreur"
        s.viewingSaveTimeline = makeSave("Farm_12345")
        s.viewingThaiMod = nil

        #expect(s.pendingModFocus == "X")
        #expect(s.pendingTranslationFocus == "Y")
        #expect(s.pendingConfigFocus == "Z")
        #expect(s.pendingModDetailFocus == "W")
        #expect(s.pendingDetailTab == .translation)
        #expect(s.pendingTranslationDiffFilter == .state(.missing))
        #expect(s.pendingLogFocus == "erreur")
        #expect(s.viewingSaveTimeline?.folderName == "Farm_12345")
    }

    // MARK: - Les deux canaux : posé par verbe, effacé par consommation.

    @Test func consommerEffaceLeCanalDuBilan() {
        let s = NavigationStore()
        s.openReportDetail(for: "ModA")
        #expect(s.reportDetailFocus == "ModA")
        s.consumeReportDetailFocus()
        #expect(s.reportDetailFocus == nil)
    }

    @Test func requestTabPoseEtConsommerEfface() {
        let s = NavigationStore()
        s.requestTab(.mods)
        #expect(s.pendingTabRequest == .mods)
        s.consumePendingTabRequest()
        #expect(s.pendingTabRequest == nil)
    }

    /// Les deux canaux sont **distincts** : poser l'un ne déborde pas sur
    /// l'autre — une requête d'onglet qui atterrirait dans le canal du bilan
    /// (ou l'inverse) ferait ouvrir une fiche au retour d'un bilan.
    @Test func lesDeuxCanauxNeDebordentPas() {
        let s = NavigationStore()
        s.requestTab(.mods)
        #expect(s.reportDetailFocus == nil)
        s.openReportDetail(for: "ModB")
        #expect(s.pendingTabRequest == .mods)
        #expect(s.reportDetailFocus == "ModB")
    }

    // MARK: - Fixtures

    private func makeSave(_ folderName: String) -> SaveGameInfo {
        SaveGameInfo(
            folderName: folderName,
            fileURL: URL(fileURLWithPath: "/tmp/\(folderName)"),
            lastModified: Date(timeIntervalSince1970: 0),
            playerName: "P", farmName: "F", favoriteThing: "T",
            money: 500, spouse: "", maxHealth: 100, maxStamina: 270,
            goldenWalnuts: 0, qiGems: 0, clubCoins: 0, totalMoneyEarned: 0,
            year: 2, season: 1, day: 3, whichFarm: 0)
    }
}
