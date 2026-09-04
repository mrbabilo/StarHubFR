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

    /// Le croisement ne sait rien d'un mod dont le dossier ne figure dans aucun
    /// relevé : il ne peut pas dire s'il tournait en silence, donc il ne désigne
    /// aucun déclencheur. C'est pourquoi l'appelant doit relever **tout** ce qui
    /// était actif sur le disque — essai *et* mods hors périmètre — et non le
    /// seul essai : plus de la moitié du parc n'est pas candidate, et un pack de
    /// contenu incriminé aurait une colonne vide sans que rien ne le dise.
    @Test func aBlamedFolderMissingFromTheRecordsNamesNoTrigger() {
        // Un pack de contenu se plaint quand LetsMoveIt tourne, se tait sans
        // lui — mais les relevés ne portent que les candidats.
        let partial: [Step] = [
            (enabled: ["LetsMoveIt", "Autre"],
             blamed: ["[CP] Pack": "champ inconnu"], stillBroken: true),
            (enabled: ["Autre"], blamed: [:], stillBroken: false),
        ]
        let blind = BisectionEvidence.analyse(partial, resolve: identity)
        #expect(blind.first?.name == "[CP] Pack")
        #expect(blind.first?.appearsOnlyWith.isEmpty == true)

        // Les mêmes étapes, relevées avec l'état complet du disque : le
        // déclencheur apparaît.
        let complete: [Step] = [
            (enabled: ["[CP] Pack", "LetsMoveIt", "Autre"],
             blamed: ["[CP] Pack": "champ inconnu"], stillBroken: true),
            (enabled: ["[CP] Pack", "Autre"], blamed: [:], stillBroken: false),
        ]
        let seeing = BisectionEvidence.analyse(complete, resolve: identity)
        #expect(seeing.first?.appearsOnlyWith == ["LetsMoveIt"])
    }

    @Test func aModNeverBlamedWhileBrokenIsNotListed() {
        let steps: [Step] = [
            (enabled: ["A"], blamed: ["A": "x"], stillBroken: false),
        ]
        #expect(BisectionEvidence.analyse(steps, resolve: identity).isEmpty)
    }
}
