import Testing
import Foundation
@testable import StarHubTHCore

/// Les lignes de mise à jour, et l'état des deux passes qui les produisent.
///
/// Les règles de calcul sont prouvées ailleurs (`NexusUpdateConsolidation`,
/// `AffirmedUpdates`, `NexusResume`) ; ici, c'est que le store les publie
/// ensemble et que le **verrou à deux détenteurs** tienne — la reprise Nexus
/// démarre pendant la passe smapi.io, et le relâchement de la première ne
/// doit pas éteindre le voyant de la seconde.
@Suite struct ModUpdateStoreTests {

    private func update(_ id: String) -> NexusUpdateChecker.ModUpdate {
        NexusUpdateChecker.ModUpdate(uniqueId: id, name: id, installedVersion: "1.0",
                                     latestVersion: "2.0", nexusModId: "1",
                                     url: "https://example.invalid", uploadedTime: nil)
    }

    private func unverifiable(_ id: String) -> SmapiVerdicts.Unverifiable {
        .init(uniqueId: id, name: id, blocker: .sourceNotFound)
    }

    // MARK: - Les deux moitiés de la partition

    /// Actives et en veille sortent d'une **même** partition : publiées
    /// séparément, un instant de rendu verrait un mod dans les deux.
    @Test func thePartitionPublishesBothHalvesAtOnce() {
        let s = ModUpdateStore()
        s.setPartition(active: [update("actif")], sleeping: [update("veille")])
        #expect(s.updates.map(\.uniqueId) == ["actif"])
        #expect(s.snoozed.map(\.uniqueId) == ["veille"])
    }

    /// Une seconde partition **remplace** : un mod réveillé ne doit pas
    /// rester dans la moitié en veille de la passe d'avant.
    @Test func aSecondPartitionReplacesBothHalves() {
        let s = ModUpdateStore()
        s.setPartition(active: [], sleeping: [update("dort")])
        s.setPartition(active: [update("dort")], sleeping: [])
        #expect(s.updates.map(\.uniqueId) == ["dort"])
        #expect(s.snoozed.isEmpty)
    }

    // MARK: - Les invérifiables et leur retrait ciblé

    /// Nexus tranche pour une partie seulement : **les autres restent dus**.
    /// Un test qui les règle tous passerait aussi sur une liste vidée en bloc.
    @Test func settlingRemovesOnlyTheNamedOnes() {
        let s = ModUpdateStore()
        s.setUnverifiable([unverifiable("tranche"), unverifiable("reste")])
        s.settle(["tranche"])
        #expect(s.unverifiable.map(\.uniqueId) == ["reste"])
    }

    /// Une reprise qui n'a rien tranché ne touche à rien.
    @Test func settlingNothingLeavesTheListAlone() {
        let s = ModUpdateStore()
        s.setUnverifiable([unverifiable("a"), unverifiable("b")])
        s.settle([])
        #expect(s.unverifiable.count == 2)
    }

    // MARK: - Le verrou à deux détenteurs

    @Test func openingACheckClearsThePreviousError() {
        let s = ModUpdateStore()
        s.setCheckError("boum")
        s.beginCheck()
        #expect(s.isChecking)
        #expect(s.checkError == nil)
    }

    /// Le cas qui porte : la reprise Nexus est partie **pendant** la passe
    /// smapi.io. Quand celle-ci se referme, le voyant doit rester allumé —
    /// sinon le bouton « Vérifier » réapparaît alors que Nexus est encore
    /// interrogé page par page, et un second passage complet peut démarrer
    /// par-dessus, aux dépens du quota.
    @Test func aFallbackInFlightHoldsTheLightAgainstTheFirstPassRelease() {
        let s = ModUpdateStore()
        s.beginCheck(progress: UpdateCheckProgress(done: 0, total: 10))
        s.beginFallback(pages: 3)
        s.endCheck()                       // la passe smapi.io se referme
        #expect(s.isChecking)              // … mais la reprise tient le voyant
        #expect(s.progress == UpdateCheckProgress(done: 0, total: 3))
    }

    /// Sans reprise en vol, la passe se referme normalement.
    @Test func withoutAFallbackTheFirstPassReleasesTheLight() {
        let s = ModUpdateStore()
        s.beginCheck(progress: UpdateCheckProgress(done: 1, total: 10))
        s.endCheck()
        #expect(s.isChecking == false)
        #expect(s.progress == nil)
    }

    /// C'est la reprise qui relâche les deux. Elle a deux sorties — dernière
    /// page atteinte, et abandon sur limitation de débit : un drapeau resté
    /// levé bloquerait la vérification « en cours » pour la session.
    @Test func theFallbackReleasesEverythingWhenItEnds() {
        let s = ModUpdateStore()
        s.beginCheck()
        s.beginFallback(pages: 2)
        s.endFallback()
        #expect(s.isChecking == false)
        #expect(s.progress == nil)
        #expect(s.fallbackInFlight == false)
        // Et une passe suivante peut de nouveau se refermer toute seule.
        s.beginCheck()
        s.endCheck()
        #expect(s.isChecking == false)
    }
}
