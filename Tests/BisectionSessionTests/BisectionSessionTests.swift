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

    /// La barre de progression doit toujours dire combien d'étapes restent.
    /// ⌈log₂(n)⌉ suppose que l'ensemble suspect se divise à chaque étape ; la
    /// fermeture vers le haut peut le faire **grossir** (un essai ramène les
    /// dépendances restées dehors, et si la panne persiste elles deviennent
    /// suspectes à leur tour). Sans garde, la carte affichait « étape 3 sur 2 ».
    @Test func theAnnouncedTotalNeverFallsBehindTheCurrentStep() {
        // Chaîne A ← B ← C ← D : chacun a besoin du précédent. ⌈log₂ 4⌉ = 2.
        let a = BisectionCandidate(folderName: "A", uniqueIds: ["a"], requires: [])
        let b = BisectionCandidate(folderName: "B", uniqueIds: ["b"], requires: ["a"])
        let c = BisectionCandidate(folderName: "C", uniqueIds: ["c"], requires: ["b"])
        let d = BisectionCandidate(folderName: "D", uniqueIds: ["d"], requires: ["c"])
        var s = BisectionSession(candidates: [a, b, c, d])

        s.record(.stillBroken)                         // reproduction
        #expect(s.state == .trial(step: 1, total: 2))  // essai = {A, B}

        s.record(.fixed)                               // suspects = {C, D}
        // L'essai {C} ne peut pas tourner seul : il embarque B, donc A.
        #expect(Set(s.foldersToEnable) == ["A", "B", "C"])
        #expect(s.state == .trial(step: 2, total: 2))

        s.record(.stillBroken)                         // suspects = {A, B, C} : ça grossit
        // Avant correction : « étape 3 sur 2 ».
        #expect(s.state == .trial(step: 3, total: 3))
    }

    @Test func theStepNeverOvertakesTheTotalOnALongChain() {
        // Même mécanique, chaîne plus longue et verdicts arbitraires : à aucun
        // moment l'étape annoncée ne doit dépasser le total annoncé.
        let chain = (0..<8).map { i in
            BisectionCandidate(folderName: "M\(i)",
                               uniqueIds: ["m\(i)"],
                               requires: i == 0 ? [] : ["m\(i - 1)"])
        }
        var s = BisectionSession(candidates: chain)
        s.record(.stillBroken)
        var guardCount = 0
        while case .trial(let step, let total) = s.state, guardCount < 40 {
            #expect(step <= total, "étape \(step) annoncée sur un total de \(total)")
            guardCount += 1
            // Alterne les réponses pour promener la recherche dans les deux sens.
            s.record(guardCount.isMultiple(of: 2) ? .fixed : .stillBroken)
        }
        #expect(guardCount < 40, "la recherche n'a pas terminé")
    }

    @Test func aSingleCandidateGoesStraightToVerification() {
        // Rien à couper en deux : la session doit vérifier directement, pas
        // conclure « pas de réponse simple » — ce qui arrivait quand l'essai,
        // trivialement égal à l'ensemble suspect, déclenchait la garde de grappe.
        var s = BisectionSession(candidates: [
            BisectionCandidate(folderName: "Solo", uniqueIds: ["solo"], requires: [])
        ])
        s.record(.stillBroken)                       // reproduction
        #expect(s.state == .confirming(folderName: "Solo"))
        #expect(s.foldersToEnable.isEmpty)           // tout sauf lui : il est seul
        s.record(.fixed)                             // sans lui, tout va bien
        #expect(s.state == .concluded(folderName: "Solo"))
    }
}
