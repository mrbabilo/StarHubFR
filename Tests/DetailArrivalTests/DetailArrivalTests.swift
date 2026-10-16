import Testing
@testable import StarHubTHCore

/// N-03 / N-05 (audit UX 2026-10-16) : une porte qui désigne un problème du
/// mod ouvre l'onglet du geste qui le règle ; une porte qui désigne le mod
/// ouvre l'Aperçu.
struct DetailArrivalTests {

    @Test func doorsThatNameTheModOpenTheOverview() {
        for door: DetailDoor in [.listRow, .palette, .installReport, .saveFootprint, .extensionSettings] {
            #expect(DetailArrival.tab(for: door) == .overview, "\(door)")
        }
    }

    /// Le bilan d'installation annonce un delta de clés, montré dans l'Aperçu :
    /// il ouvrait Santé.
    @Test func theInstallReportLandsWhereItsDeltaIsShown() {
        #expect(DetailArrival.tab(for: .installReport) == .overview)
    }

    @Test func aDependencyProblemOpensTheDependenciesTab() {
        #expect(DetailArrival.tab(for: .alert(dependency: true)) == .dependencies)
        #expect(DetailArrival.tab(for: .anomalyBanner(dependencyOnly: true)) == .dependencies)
        #expect(DetailArrival.tab(for: .alert(dependency: false)) == .health)
        #expect(DetailArrival.tab(for: .anomalyBanner(dependencyOnly: false)) == .health)
    }

    @Test func eachRemainingDoorKeepsTheTabOfItsGesture() {
        #expect(DetailArrival.tab(for: .affirmedUpdate) == .history)
        #expect(DetailArrival.tab(for: .nexusUpdate) == .history)
        #expect(DetailArrival.tab(for: .unverifiable) == .management)
        #expect(DetailArrival.tab(for: .frenchTranslations) == .translation)
        #expect(DetailArrival.tab(for: .compatibilityCard) == .health)
        #expect(DetailArrival.tab(for: .performance) == .health)
    }

    /// Une anomalie mixte (dépendance **et** erreurs) reste sur Santé.
    @Test func onlyAPureDependencyIssueIsDependencyOnly() {
        let pure = ModAnomaly(severity: .error, errorCount: 0, warningCount: 0,
                              hasDependencyIssue: true, isUnloadable: false)
        let mixed = ModAnomaly(severity: .error, errorCount: 2, warningCount: 0,
                               hasDependencyIssue: true, isUnloadable: false)
        #expect(pure.isDependencyOnly)
        #expect(!mixed.isDependencyOnly)
    }
}
