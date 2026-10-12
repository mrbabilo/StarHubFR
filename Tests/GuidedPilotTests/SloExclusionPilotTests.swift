import Testing
@testable import StarHubTHCore

/// P1 T7 — le pilotage exclut les autres travaux de performance ; le jeu
/// ouvert prime toujours (ordre des gardes : jeu > pilotage > benchmark > …).
@Suite struct SloExclusionPilotTests {
    @Test func pilotActiveBlocksEverythingElse() {
        #expect(SloDiagnosticExclusion.busyReason(gameRunning: false, benchmarkActive: false,
                                                  bisectionActive: false, guidedPlanPending: false,
                                                  otherReason: nil, pilotActive: true)
                == "guided-pilot-active")
        #expect(SloDiagnosticExclusion.busyReason(gameRunning: true, benchmarkActive: false,
                                                  bisectionActive: false, guidedPlanPending: false,
                                                  otherReason: nil, pilotActive: true)
                == "game-running")
        #expect(SloDiagnosticExclusion.busyReason(gameRunning: false, benchmarkActive: true,
                                                  bisectionActive: false, guidedPlanPending: true,
                                                  otherReason: nil, pilotActive: true)
                == "guided-pilot-active")
    }

    @Test func pilotKeyMatchesTheRunner() {
        #expect(GuidedPilotRunner.busyKey == "guided-pilot-active")
    }
}
