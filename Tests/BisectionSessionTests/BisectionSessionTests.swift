import Testing
import Foundation
@testable import StarHubTHCore

struct BisectionSessionTests {
    /// Trois mods sans dépendance entre eux.
    private func simple(_ names: String...) -> [BisectionCandidate] {
        names.map { BisectionCandidate(folderName: $0, uniqueIds: [$0.lowercased()], requires: []) }
    }

    @Test func startsByReproducingWithEverythingEnabled() {
        let s = BisectionSession(candidates: simple("A", "B", "C", "D"))
        #expect(s.state == .reproducing)
        #expect(Set(s.foldersToEnable) == ["A", "B", "C", "D"])
    }

    @Test func aProblemThatDoesNotComeBackStopsTheSession() {
        // Sans reproduction, une panne intermittente ferait accuser un innocent.
        var s = BisectionSession(candidates: simple("A", "B"))
        s.record(.fixed)
        #expect(s.state == .notReproducible)
    }

    @Test func halvesTheSetAfterReproducing() {
        var s = BisectionSession(candidates: simple("A", "B", "C", "D"))
        s.record(.stillBroken)
        guard case .trial(let step, let total) = s.state else {
            Issue.record("attendu une étape d'essai"); return
        }
        #expect(step == 1)
        #expect(total == 2)                       // ceil(log2(4))
        #expect(s.foldersToEnable.count == 2)
    }

    @Test func convergesToASingleFolder() {
        var s = BisectionSession(candidates: simple("A", "B", "C", "D"))
        s.record(.stillBroken)                    // reproduction
        s.record(.stillBroken)                    // coupable dans la moitié testée
        s.record(.stillBroken)
        guard case .confirming(let name) = s.state else {
            Issue.record("attendu la confirmation, obtenu \(s.state)"); return
        }
        #expect(["A", "B"].contains(name))
    }

    @Test func confirmationEnablesEverythingExceptTheSuspect() {
        var s = BisectionSession(candidates: simple("A", "B"))
        s.record(.stillBroken)
        s.record(.stillBroken)
        guard case .confirming(let name) = s.state else {
            Issue.record("attendu la confirmation"); return
        }
        #expect(!s.foldersToEnable.contains(name))
        #expect(s.foldersToEnable.count == 1)
    }

    @Test func confirmationThatFixesTheProblemConcludes() {
        var s = BisectionSession(candidates: simple("A", "B"))
        s.record(.stillBroken)
        s.record(.stillBroken)
        s.record(.fixed)                          // sans lui, tout va bien
        guard case .concluded(let name) = s.state else {
            Issue.record("attendu une conclusion"); return
        }
        #expect(["A", "B"].contains(name))
    }

    @Test func confirmationThatFailsIsInconclusive() {
        // Deux mods qui ne s'entendent qu'ensemble : la méthode ne peut pas
        // conclure, et doit le dire au lieu d'accuser.
        var s = BisectionSession(candidates: simple("A", "B"))
        s.record(.stillBroken)
        s.record(.stillBroken)
        s.record(.stillBroken)
        #expect(s.state == .inconclusive)
    }

    @Test func aPausedFolderTakesItsDependentsWithIt() {
        // B a besoin de A. Un essai qui exclut A doit aussi exclure B, sinon B
        // remonte une erreur de dépendance manquante qui imite la panne.
        // On éprouve la fermeture directement : passer par une session ferait
        // dépendre l'assertion de la moitié tirée, et le test pourrait ne rien
        // vérifier du tout.
        let a = BisectionCandidate(folderName: "A", uniqueIds: ["fw"], requires: [])
        let b = BisectionCandidate(folderName: "B", uniqueIds: ["b"], requires: ["fw"])
        #expect(BisectionSession.closed([b], within: [a, b]).isEmpty)
        #expect(BisectionSession.closed([a, b], within: [a, b]).count == 2)
        // Un besoin que personne parmi les candidats ne fournit (mod hors
        // périmètre, resté actif) ne doit pas exclure.
        let c = BisectionCandidate(folderName: "C", uniqueIds: ["c"], requires: ["hors.perimetre"])
        #expect(BisectionSession.closed([c], within: [c]).count == 1)
    }

    @Test func dependentsSitNextToTheirFramework() {
        // Le tri par grappe évite qu'une coupe malheureuse vide un essai.
        let candidates = [
            BisectionCandidate(folderName: "X", uniqueIds: ["x"], requires: []),
            BisectionCandidate(folderName: "B", uniqueIds: ["b"], requires: ["fw"]),
            BisectionCandidate(folderName: "Y", uniqueIds: ["y"], requires: []),
            BisectionCandidate(folderName: "A", uniqueIds: ["fw"], requires: []),
        ]
        let ordered = BisectionSession.clustered(candidates).map(\.folderName)
        let iA = ordered.firstIndex(of: "A")!, iB = ordered.firstIndex(of: "B")!
        #expect(abs(iA - iB) == 1)
    }

    @Test func anEmptySetIsImmediatelyInconclusive() {
        var s = BisectionSession(candidates: [])
        s.record(.stillBroken)
        #expect(s.state == .inconclusive)
    }
}
