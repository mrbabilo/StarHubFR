import Testing
import Foundation
@testable import StarHubTHCore

/// Retour d'écran du 2026-10-13 : la fin de série doit montrer la paire A/B
/// jouée — ses deux plans et le nom du changement voyagent avec l'état.
@Suite struct GuidedPilotPairTests {
    private func begun() -> GuidedPilotPlan {
        var plan = GuidedPilotPlan.initial
        plan.begin(draft: .init(name: "A", role: .before, location: "Farm", pairedWith: nil),
                   gesture: .applyProfile(baseProfileIds: ["x"]), changeLabel: "BENCH+",
                   now: Date(timeIntervalSince1970: 0))
        return plan
    }

    @Test func eachSideRecordsItsOwnPlan() {
        var plan = begun()
        let before = UUID(), after = UUID()
        plan.setSidePlan(before)
        plan.sideFinished(now: Date(timeIntervalSince1970: 60))
        plan.setSidePlan(UUID())   // applying : aucun côté en vol, ignoré
        plan.gestureApplied(now: Date(timeIntervalSince1970: 61))
        plan.setSidePlan(after)
        plan.sideFinished(now: Date(timeIntervalSince1970: 120))
        #expect(plan.phase == .reporting)
        #expect(plan.beforePlanId == before)
        #expect(plan.afterPlanId == after)
        #expect(plan.changeLabel == "BENCH+")
        plan.finish()
        #expect(plan.afterPlanId == nil && plan.changeLabel == nil && plan.beforePlanId == nil)
    }

    /// Le parc n'est dit « sur B » que si le geste a réussi : un geste raté
    /// l'a laissé à moitié, les boutons ne doivent pas nommer le profil.
    @Test func theParcIsOnSideBOnlyAfterASuccessfulGesture() {
        var plan = begun()
        #expect(!plan.parcIsOnAfterSide)
        plan.sideFinished(now: Date(timeIntervalSince1970: 60))
        var failed = plan
        failed.gestureFailed(.applyFailed, now: Date(timeIntervalSince1970: 61))
        #expect(failed.gestureRan && !failed.parcIsOnAfterSide)
        plan.gestureApplied(now: Date(timeIntervalSince1970: 61))
        #expect(plan.parcIsOnAfterSide)
        plan.sideFailed(.gameQuit, now: Date(timeIntervalSince1970: 90))
        #expect(plan.parcIsOnAfterSide)   // B a échoué, le parc est resté sur B
    }

    /// Un état écrit avant ces champs (sans `afterPlanId` ni `changeLabel`)
    /// se relit toujours : la reprise après plantage n'est pas perdue.
    @Test func aStateSavedWithoutTheNewFieldsStillDecodes() throws {
        var plan = begun()
        plan.setSidePlan(UUID())
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        #expect(object.removeValue(forKey: "changeLabel") != nil)
        object.removeValue(forKey: "afterPlanId")
        let old = try JSONSerialization.data(withJSONObject: object)
        let back = try JSONDecoder().decode(GuidedPilotPlan.self, from: old)
        #expect(back.phase == plan.phase)
        #expect(back.beforePlanId == plan.beforePlanId)
        #expect(back.changeLabel == nil)
    }
}

/// Le verdict en tête de la fin de série : la fluidité de B face à A.
@Suite struct GuidedPilotVerdictTests {
    @Test func noModChangeIsIdenticalWhateverTheNumbers() {
        #expect(GuidedPilotVerdict.of(changeCount: 0, frameOutcomes: [.improved, .improved]) == .identical)
    }

    @Test func frameOutcomesDecide() {
        #expect(GuidedPilotVerdict.of(changeCount: 3, frameOutcomes: [.improved, .noClearDifference]) == .smoother)
        #expect(GuidedPilotVerdict.of(changeCount: 3, frameOutcomes: [.noClearDifference, .worsened]) == .lessSmooth)
        #expect(GuidedPilotVerdict.of(changeCount: 3, frameOutcomes: [.improved, .worsened]) == .mixed)
        #expect(GuidedPilotVerdict.of(changeCount: 3, frameOutcomes: [.noClearDifference, .noClearDifference])
                == .noDifference)
    }

    /// Sans diff d'inventaire (`nil`), on ne prétend pas « identique ».
    @Test func unknownOrUnusableIsInconclusive() {
        #expect(GuidedPilotVerdict.of(changeCount: nil, frameOutcomes: [.noClearDifference, .noClearDifference])
                == .noDifference)
        #expect(GuidedPilotVerdict.of(changeCount: 2, frameOutcomes: [.noClearDifference, .insufficient]) == .inconclusive)
        #expect(GuidedPilotVerdict.of(changeCount: 2, frameOutcomes: []) == .inconclusive)
        #expect(GuidedPilotVerdict.of(changeCount: 2, frameOutcomes: [.variable, .incomparable]) == .inconclusive)
    }
}
