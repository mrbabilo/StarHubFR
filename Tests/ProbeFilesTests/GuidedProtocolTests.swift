import Testing
import Foundation
@testable import StarHubTHCore

struct GuidedProtocolTests {
    private func measurement(_ role: ProbeMeasurement.Role, outcome: ProbeMeasurement.Outcome = .stable,
                             at seconds: TimeInterval, pairedWith: UUID? = nil) -> ProbeMeasurement {
        ProbeMeasurement(name: "\(role)", start: Date(timeIntervalSince1970: seconds), end: nil,
                         keptAt: [], outcome: outcome, role: role, pairedWith: pairedWith, location: "Beach")
    }

    @Test func excludedLocationsFallBackToTheFarm() {
        for name in ["UndergroundMine42", "VolcanoDungeon3", "Temp", "", nil] as [String?] {
            #expect(GuidedProtocol.safeLocation(name) == "Farm")
        }
        #expect(GuidedProtocol.safeLocation("Town") == "Town")
        #expect(GuidedProtocol.locations.first == "Farm")
    }

    @Test func stateShowsAPendingPlanFirst() {
        let plan = GuidedPlan(id: UUID(), name: "p", role: .before, location: "Farm", pairedWith: nil,
                              createdAt: .now)
        #expect(GuidedProtocol.state(plan: plan, measurements: []) == .planPending(plan))
    }

    /// Étape 1 faite : la dernière mesure close est un « avant » que rien ne désigne.
    @Test func beforeDoneUntilAnAfterPointsAtIt() {
        let before = measurement(.before, at: 100)
        #expect(GuidedProtocol.state(plan: nil, measurements: [before]) == .beforeDone(before))
        let after = measurement(.after, at: 200, pairedWith: before.id)
        #expect(GuidedProtocol.state(plan: nil, measurements: [before, after]) == .idle)
        let dropped = measurement(.before, outcome: .abandoned, at: 300)
        #expect(GuidedProtocol.state(plan: nil, measurements: [before, after, dropped]) == .idle)
    }

    @Test func readinessReadsTheInstalledManifest() {
        #expect(GuidedProtocol.readiness(probeVersion: nil, isEnabled: false) == .missing)
        #expect(GuidedProtocol.readiness(probeVersion: "0.5.0", isEnabled: false) == .paused)
        #expect(GuidedProtocol.readiness(probeVersion: "0.4.13", isEnabled: true) == .outdated("0.4.13"))
        #expect(GuidedProtocol.readiness(probeVersion: "0.5.0", isEnabled: true) == .ready)
        #expect(GuidedProtocol.supportsGuidance("0.10.0"))
        #expect(GuidedProtocol.supportsGuidance("1.0"))
        #expect(!GuidedProtocol.supportsGuidance("0.4.99"))
        #expect(!GuidedProtocol.supportsGuidance("abc"))
    }
}
