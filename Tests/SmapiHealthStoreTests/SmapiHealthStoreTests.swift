import Testing
import Foundation
@testable import StarHubTHCore

/// L'état de santé que le journal SMAPI rend : diagnostics, fraîcheur,
/// alertes, conflits Content Patcher — et le verrou du bouton de relecture.
///
/// Les décisions sont prouvées dans `SmapiHealthFoldTests` ; ici, c'est que le
/// store les applique, et que ce qui doit changer **ensemble** change ensemble.
@Suite struct SmapiHealthStoreTests {

    private func diag() -> SmapiDiagnostics {
        var d = SmapiDiagnostics()
        d.smapiVersion = "4.1.10"
        return d
    }

    @Test func aNewStoreKnowsNothing() {
        let s = SmapiHealthStore()
        #expect(s.diagnostics == nil)
        #expect(s.logDate == nil)
        #expect(s.isStale == false)
        #expect(s.errors.isEmpty)
        #expect(s.contentPatcherConflicts.isEmpty)
    }

    /// Date, diagnostics et conflits viennent d'une **même** lecture : les
    /// laisser diverger afficherait les conflits d'avant à côté d'une date
    /// d'aujourd'hui.
    @Test func aReadAppliesDateDiagnosticsAndConflictsTogether() {
        let s = SmapiHealthStore()
        let when = Date(timeIntervalSince1970: 100)
        s.apply(diagnostics: diag(), logDate: when, isStale: true, conflicts: [],
                outOfDate: [])
        #expect(s.diagnostics?.smapiVersion == "4.1.10")
        #expect(s.logDate == when)
        #expect(s.isStale)
    }

    /// Un journal disparu remet tout à zéro — sans quoi la fiche afficherait
    /// les conflits de la lecture précédente à côté d'une date à `nil`.
    @Test func aMissingLogResetsEverythingItHadRead() {
        let s = SmapiHealthStore()
        s.apply(diagnostics: diag(), logDate: Date(), isStale: true, conflicts: [],
                outOfDate: [])
        _ = s.apply(errors: ["boum"])
        s.reset()
        #expect(s.diagnostics == nil)
        #expect(s.logDate == nil)
        #expect(s.isStale == false)
        #expect(s.errors.isEmpty)
        #expect(s.contentPatcherConflicts.isEmpty)
    }

    // MARK: - Les mods perimes, qui viennent de la meme lecture

    private func update(_ name: String) -> ModUpdateInfo {
        ModUpdateInfo(name: name, version: "1.0", url: "https://example.invalid")
    }

    /// Le bloc « You can update N mods » sort de la **meme** lecture que la
    /// date et les diagnostics. Publie a part, il restait celui d'avant a
    /// cote d'une date fraiche — et la pastille d'accueil, qui compte
    /// `outOfDateMods + nexusUpdates`, annoncait un chiffre perime.
    @Test func aReadAppliesOutOfDateModsWithTheRest() {
        let s = SmapiHealthStore()
        let when = Date(timeIntervalSince1970: 100)
        s.apply(diagnostics: diag(), logDate: when, isStale: false,
                conflicts: [], outOfDate: [update("Kids for the School")])
        #expect(s.outOfDateMods.map(\.name) == ["Kids for the School"])
        #expect(s.logDate == when)
    }

    /// Une lecture plus recente **remplace** la liste : deux appels ne
    /// l'accumulent pas, et une lecture qui ne signale plus rien la vide.
    @Test func aNewerReadReplacesTheListInsteadOfAddingToIt() {
        let s = SmapiHealthStore()
        s.apply(diagnostics: nil, logDate: Date(timeIntervalSince1970: 100),
                isStale: false, conflicts: [], outOfDate: [update("Avant")])
        s.apply(diagnostics: nil, logDate: Date(timeIntervalSince1970: 200),
                isStale: false, conflicts: [], outOfDate: [update("Apres")])
        #expect(s.outOfDateMods.map(\.name) == ["Apres"])
    }

    /// Le tri vit **ici**, pas chez les appelants : deux tris a deux endroits
    /// divergeraient un jour, et les deux chemins de lecture du journal
    /// doivent rendre le meme ordre.
    @Test func theListIsSortedByNameWhoeverSuppliesIt() {
        let s = SmapiHealthStore()
        s.apply(diagnostics: nil, logDate: nil, isStale: false, conflicts: [],
                outOfDate: [update("Zeta"), update("alpha"), update("Mu")])
        #expect(s.outOfDateMods.map(\.name) == ["alpha", "Mu", "Zeta"])
    }

    /// Journal disparu : la liste part avec le reste. Sans ca, deux gestes
    /// la ou le store en promet un.
    @Test func aMissingLogAlsoDropsTheOutOfDateMods() {
        let s = SmapiHealthStore()
        s.apply(diagnostics: diag(), logDate: Date(), isStale: true,
                conflicts: [], outOfDate: [update("Perime")])
        s.reset()
        #expect(s.outOfDateMods.isEmpty)
    }

    // MARK: - Les alertes et leur journalisation

    @Test func thefirstReadLogsEveryAlert() {
        let s = SmapiHealthStore()
        #expect(s.apply(errors: ["a", "b"]) == ["a", "b"])
        #expect(s.errors == ["a", "b"])
    }

    @Test func readingTheSameAlertsAgainLogsNothing() {
        let s = SmapiHealthStore()
        _ = s.apply(errors: ["a", "b"])
        #expect(s.apply(errors: ["a", "b"]).isEmpty)
        // La liste affichée, elle, est bien republiée.
        #expect(s.errors == ["a", "b"])
    }

    @Test func aReplacedAlertIsLogged() {
        let s = SmapiHealthStore()
        _ = s.apply(errors: ["a", "b"])
        #expect(s.apply(errors: ["a", "c"]) == ["c"])
    }

    /// ⚠️ Comportement **conservé tel quel** : un journal disparu n'oublie pas
    /// ce qui a déjà été journalisé, donc les mêmes alertes revenant après un
    /// reset ne sont pas re-journalisées. Le test dit ce que le code fait.
    @Test func aResetDoesNotForgetWhatWasAlreadyLogged() {
        let s = SmapiHealthStore()
        _ = s.apply(errors: ["a"])
        s.reset()
        #expect(s.apply(errors: ["a"]).isEmpty)
    }

    // MARK: - Le verrou de relecture

    @Test func aSecondRefreshIsRefusedWhileTheFirstRuns() {
        let s = SmapiHealthStore()
        #expect(s.beginRefresh() == true)
        #expect(s.beginRefresh() == false)
        s.endRefresh()
        #expect(s.isRefreshing == false)
        #expect(s.beginRefresh() == true)
    }
}
