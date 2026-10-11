import Testing
import Foundation
@testable import StarHubTHCore

/// P1 — `guided-plan.json` v2 : champs de pilotage `AutoPilot` et `Warp`,
/// tolérants dans les deux sens (spec §5 : vieille sonde + plan v2 = protocole
/// humain, champs ignorés).
@Suite struct GuidedPlanV2Tests {
    @Test func v2RoundTripKeepsPilotFields() throws {
        let plan = GuidedPlan(id: UUID(), name: "P", role: .before, location: "Farm",
                              pairedWith: nil, saveName: "Ferme_123",
                              createdAt: Date(timeIntervalSince1970: 1_000_000),
                              autoPilot: true, warp: .init(x: 64, y: 15))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try plan.write(to: url)
        let back = GuidedPlan.load(from: url)
        #expect(back == plan)
        #expect(back?.autoPilot == true)
        #expect(back?.warp == GuidedPlanWarp(x: 64, y: 15))
    }

    @Test func v1PlanDecodesWithPilotFieldsNil() throws {
        let v1 = """
        {"Version":1,"Id":"\(UUID().uuidString)","Name":"P","Role":"before",
         "Location":"Town","CreatedAt":"2026-10-11T20:00:00Z"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let plan = try decoder.decode(GuidedPlan.self, from: v1)
        #expect(plan.autoPilot == nil && plan.warp == nil)
    }

    @Test func warpAnchorsCoverEveryGuidedLocation() {
        for place in GuidedProtocol.locations {
            #expect(GuidedProtocol.warpAnchor(for: place) != nil)
        }
    }
}
