import Testing
import Foundation
@testable import StarHubTHCore

/// L'analyse croise les relevés d'étape pour répondre à la question que pose
/// l'utilisateur : « qu'est-ce qui fait que cette erreur cesse d'apparaître ? »
struct BisectionEvidenceTests {
    private typealias Step = (enabled: Set<String>, blamed: [String: String], stillBroken: Bool)

    /// Les noms du journal sont ceux des dossiers dans ces cas de test.
    private let identity: (String) -> String? = { $0 }

    @Test func namesWhatMustBeOnForTheErrorToAppear() {
        // Gunther se plaint quand LetsMoveIt tourne, et se tait sans lui.
        let steps: [Step] = [
            (enabled: ["Gunther", "LetsMoveIt", "Autre"],
             blamed: ["Gunther": "API incompatible"], stillBroken: true),
            (enabled: ["Gunther", "LetsMoveIt"],
             blamed: ["Gunther": "API incompatible"], stillBroken: true),
            (enabled: ["Gunther", "Autre"], blamed: [:], stillBroken: false),
        ]
        let out = BisectionEvidence.analyse(steps, resolve: identity)
        guard let g = out.first(where: { $0.name == "Gunther" }) else {
            Issue.record("Gunther absent du relevé"); return
        }
        #expect(g.appearsOnlyWith == ["LetsMoveIt"])
        #expect(g.sample == "API incompatible")
        #expect(g.whenBroken == 2)
    }

    @Test func anIntermittentErrorIsStillReported() {
        // Règle précédente : présent à *toutes* les étapes en échec. Elle
        // éliminait exactement ce cas.
        let steps: [Step] = [
            (enabled: ["A", "B"], blamed: ["A": "boum"], stillBroken: true),
            (enabled: ["A", "B"], blamed: [:], stillBroken: true),
        ]
        let out = BisectionEvidence.analyse(steps, resolve: identity)
        #expect(out.map(\.name) == ["A"])
        #expect(out.first?.whenBroken == 1)
        #expect(out.first?.brokenSteps == 2)
    }

    @Test func aModThatComplainsEvenWhenAllIsWellTellsNothingAboutTheTrigger() {
        // Il se plaint partout : aucun déclencheur ne peut être désigné.
        let steps: [Step] = [
            (enabled: ["A", "B"], blamed: ["A": "bruit"], stillBroken: true),
            (enabled: ["A"], blamed: ["A": "bruit"], stillBroken: false),
        ]
        let out = BisectionEvidence.analyse(steps, resolve: identity)
        #expect(out.first?.appearsOnlyWith.isEmpty == true)
        #expect(out.first?.whenFine == 1)
    }

    @Test func aModNeverBlamedWhileBrokenIsNotListed() {
        let steps: [Step] = [
            (enabled: ["A"], blamed: ["A": "x"], stillBroken: false),
        ]
        #expect(BisectionEvidence.analyse(steps, resolve: identity).isEmpty)
    }
}
