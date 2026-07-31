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

    @Test func aTrialCarriesTheDependenciesItNeeds() {
        // Tester B seul embarque A.
        let a = BisectionCandidate(folderName: "A", uniqueIds: ["fw"], requires: [])
        let b = BisectionCandidate(folderName: "B", uniqueIds: ["b"], requires: ["fw"])
        let result = BisectionSession.withRequiredDependencies([b], within: [a, b]).map(\.folderName)
        #expect(result == ["A", "B"])
        // Un besoin que personne parmi les candidats ne fournit n'ajoute rien.
        let c = BisectionCandidate(folderName: "C", uniqueIds: ["c"], requires: ["hors.perimetre"])
        let result2 = BisectionSession.withRequiredDependencies([c], within: [c]).map(\.folderName)
        #expect(result2 == ["C"])
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

    @Test func aSearchWhoseCulpritNeedsAFrameworkStillConverges() {
        // Le cas qui bloquait : le coupable B a besoin du framework A, et une
        // coupe les sépare. Fermer en retirant les orphelins vidait l'essai et
        // la recherche ne convergeait plus.
        let candidates = [
            BisectionCandidate(folderName: "X", uniqueIds: ["x"], requires: []),
            BisectionCandidate(folderName: "A", uniqueIds: ["fw"], requires: []),
            BisectionCandidate(folderName: "B", uniqueIds: ["b"], requires: ["fw"]),
            BisectionCandidate(folderName: "Y", uniqueIds: ["y"], requires: []),
        ]
        var s = BisectionSession(candidates: candidates)
        s.record(.stillBroken)                       // reproduction
        var guardRail = 0
        while guardRail < 12 {
            guardRail += 1
            let enabled = Set(s.foldersToEnable)
            #expect(!enabled.isEmpty, "un essai ne doit jamais être vide")
            switch s.state {
            case .trial:
                // Le coupable est B : la panne persiste si et seulement si B tourne.
                s.record(enabled.contains("B") ? .stillBroken : .fixed)
            case .confirming:
                // Sans B, tout va bien.
                s.record(enabled.contains("B") ? .stillBroken : .fixed)
            default:
                break
            }
            if case .concluded = s.state { break }
            if case .inconclusive = s.state { break }
            if case .notReproducible = s.state { break }
        }
        #expect(s.state == .concluded(folderName: "B"))
    }

    @Test func confirmingAFrameworkAlsoPausesWhatNeedsIt() {
        // Écarter A sans écarter B ferait échouer la confirmation pour une
        // raison étrangère à A : B tournerait sans sa dépendance.
        let a = BisectionCandidate(folderName: "A", uniqueIds: ["fw"], requires: [])
        let b = BisectionCandidate(folderName: "B", uniqueIds: ["b"], requires: ["fw"])
        let x = BisectionCandidate(folderName: "X", uniqueIds: ["x"], requires: [])
        let kept = BisectionSession.excluding("A", from: [a, b, x]).map(\.folderName)
        #expect(kept == ["X"])
    }

    @Test func anEmptySetIsImmediatelyInconclusive() {
        var s = BisectionSession(candidates: [])
        s.record(.stillBroken)
        #expect(s.state == .inconclusive)
    }

    @Test func modsThatNeedEachOtherCannotBeBlamedIndividually() {
        // Dépendance mutuelle : la fermeture reconstitue la grappe depuis
        // n'importe quel sous-ensemble. Sans garde, la recherche présentait
        // indéfiniment le même essai, le compteur d'étapes filant au-delà du
        // total annoncé.
        let a = BisectionCandidate(folderName: "A", uniqueIds: ["a"], requires: ["b"])
        let b = BisectionCandidate(folderName: "B", uniqueIds: ["b"], requires: ["a"])
        let x = BisectionCandidate(folderName: "X", uniqueIds: ["x"], requires: [])
        let y = BisectionCandidate(folderName: "Y", uniqueIds: ["y"], requires: [])
        var s = BisectionSession(candidates: [a, b, x, y])
        s.record(.stillBroken)                    // reproduction
        var steps = 0
        while steps < 12 {
            steps += 1
            guard case .trial = s.state else { break }
            // Le coupable est A : la panne persiste si et seulement si A tourne.
            s.record(Set(s.foldersToEnable).contains("A") ? .stillBroken : .fixed)
        }
        // La recherche doit s'arrêter, et le dire — jamais boucler.
        #expect(s.state == .inconclusive)
        #expect(steps < 12, "la recherche n'a pas terminé")
    }
}
