import Testing
import Foundation
@testable import StarHubTHCore

/// P1 §7 — la machine pure du pilotage : transitions, watchdog, reprise.
@Suite struct GuidedPilotPlanTests {
    private func fresh() -> GuidedPilotPlan {
        var plan = GuidedPilotPlan.initial
        plan.begin(draft: .init(name: "A", role: .before, location: "Farm",
                                pairedWith: nil),
                   gesture: .pauseMod(folderName: "Stardropium", modId: "Arshia1381.Stardropium"),
                   now: Date(timeIntervalSince1970: 0))
        return plan
    }

    @Test func happyPathReachesReporting() {
        var plan = fresh()
        plan.noteProgress(now: Date(timeIntervalSince1970: 300))
        plan.sideFinished(now: Date(timeIntervalSince1970: 600))
        #expect(plan.phase == .applying)
        plan.gestureApplied(now: Date(timeIntervalSince1970: 601))
        #expect(plan.phase == .running(step: .after))
        plan.sideFinished(now: Date(timeIntervalSince1970: 1200))
        #expect(plan.phase == .reporting)
        plan.finish()
        #expect(plan.phase == .idle)
    }

    @Test func sideQuittingGameFailsWithoutGesture() {
        var plan = fresh()
        plan.sideFailed(.gameQuit, now: Date(timeIntervalSince1970: 60))
        #expect(plan.phase == .failed(.gameQuit))
        #expect(plan.gestureRan == false)
    }

    @Test func stalledAfterTenMinutesWithoutProgress() {
        var plan = fresh()
        plan.noteProgress(now: Date(timeIntervalSince1970: 10))
        #expect(plan.isStalled(now: Date(timeIntervalSince1970: 10 + 599)) == false)
        #expect(plan.isStalled(now: Date(timeIntervalSince1970: 10 + 601)))
    }

    @Test func failedGestureStopsBeforeAfterSide() {
        var plan = fresh()
        plan.sideFinished(now: Date(timeIntervalSince1970: 600))
        plan.gestureFailed(.applyFailed, now: Date(timeIntervalSince1970: 601))
        #expect(plan.phase == .failed(.applyFailed))
        plan.gestureApplied(now: Date(timeIntervalSince1970: 602))  // no-op
        #expect(plan.phase == .failed(.applyFailed))
    }

    @Test func interruptOnlyMidFlight() {
        var plan = GuidedPilotPlan.initial
        plan.interrupt()
        #expect(plan.phase == .idle)
        plan = fresh()
        plan.sideFinished(now: Date(timeIntervalSince1970: 600))
        plan.interrupt()
        #expect(plan.phase == .interrupted)
        plan = fresh()
        plan.sideFinished(now: Date(timeIntervalSince1970: 600))
        plan.gestureApplied(now: Date(timeIntervalSince1970: 601))
        plan.sideFinished(now: Date(timeIntervalSince1970: 1200))
        plan.interrupt()   // reporting n'est pas « interrompu »
        #expect(plan.phase == .reporting)
    }

    @Test func beginOnlyFromIdle() {
        var plan = fresh()
        plan.begin(draft: .init(name: "B", role: .before, location: "Town", pairedWith: nil),
                   gesture: .pauseMod(folderName: "X", modId: "x"), now: Date())
        #expect(plan.phase == .running(step: .before))  // inchangé
    }
}
