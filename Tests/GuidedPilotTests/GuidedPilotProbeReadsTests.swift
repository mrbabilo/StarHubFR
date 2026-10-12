import Testing
import Foundation
@testable import StarHubTHCore

/// P1 T7 — ce que le runtime réel lit de la sonde pour le runner : la mesure
/// du plan close, et les minutes gardées au lieu cible depuis le plan
/// (signal de vie du watchdog).
@Suite struct GuidedPilotProbeReadsTests {
    private static let base = "2026-09-28T"

    private func minute(_ at: String, location: String? = "Farm") -> ProbeMinute {
        let json = """
        {"Session":"s","At":"\(Self.base)\(at):00.0000000+02:00","WallSeconds":60,"Fps":30,
         "FrameInterval":{"Count":45,"Avg":30,"P50":30,"P99":50,"Max":60},
         "InactiveTicks":0,"HeapMB":4000,"LoadedMods":289,
         "Location":\(location.map { "\"\($0)\"" } ?? "null"),
         "MenuTicks":0,"Tick":{"Count":1000,"Avg":20,"P50":20,"P99":40,"Max":50},
         "GameTime":650}
        """
        return try! ProbeJSON.decoder().decode(ProbeMinute.self, from: Data(json.utf8))
    }

    private func plan(location: String = "Farm") -> GuidedPlan {
        GuidedPlan(id: UUID(), name: "P", role: .before, location: location, pairedWith: nil,
                   createdAt: ProbeDate.parse("\(Self.base)10:00:00.0000000+02:00")!, autoPilot: true)
    }

    @Test func onlyAFinishedMeasurementOfThisPlanCloses() {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 0)
        func measurement(_ id: UUID, _ outcome: ProbeMeasurement.Outcome) -> ProbeMeasurement {
            ProbeMeasurement(id: id, name: "P", start: start, end: start, outcome: outcome)
        }
        #expect(GuidedPilotProbeReads.measurementState(planId: id, in: [measurement(id, .stable)]) == .finished)
        #expect(GuidedPilotProbeReads.measurementState(planId: id, in: [measurement(id, .noisy)]) == .finished)
        // Abandonnée (retour au titre, jeu quitté) : elle ne se clora plus.
        #expect(GuidedPilotProbeReads.measurementState(planId: id, in: [measurement(id, .abandoned)]) == .none)
        #expect(GuidedPilotProbeReads.measurementState(planId: id, in: [measurement(UUID(), .stable)]) == .none)
    }

    @Test func keptMinutesCountOnlyTheTargetSinceThePlan() {
        let plan = plan()
        let session = ProbeSession(id: "s", minutes: [
            minute("09:58"),                    // avant le plan (et première en partie)
            minute("10:01"), minute("10:02"),
            minute("10:03", location: "Town"),  // ailleurs
            minute("10:04"),
        ], costs: [])
        #expect(GuidedPilotProbeReads.keptMinutes(plan: plan, planId: plan.id, session: session) == 3)
    }

    @Test func otherPlanOrNoSessionCountsNothing() {
        let plan = plan()
        let session = ProbeSession(id: "s", minutes: [minute("09:59"), minute("10:01")], costs: [])
        #expect(GuidedPilotProbeReads.keptMinutes(plan: plan, planId: UUID(), session: session) == 0)
        #expect(GuidedPilotProbeReads.keptMinutes(plan: nil, planId: plan.id, session: session) == 0)
        #expect(GuidedPilotProbeReads.keptMinutes(plan: plan, planId: plan.id, session: nil) == 0)
    }
}
