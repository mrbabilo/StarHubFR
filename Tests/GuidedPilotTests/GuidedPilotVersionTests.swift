import Testing
@testable import StarHubTHCore

/// P1 T8 — le pilotage exige la sonde qui l'exécute (0.9.25) ; borne
/// distincte de celle du guidage (0.5.0).
@Suite struct GuidedPilotVersionTests {
    @Test func pilotNeedsProbe0925() {
        #expect(GuidedProtocol.supportsPilot("0.9.24") == false)
        #expect(GuidedProtocol.supportsPilot("0.9.25"))
        #expect(GuidedProtocol.supportsPilot("0.10.0"))
        #expect(GuidedProtocol.supportsPilot("1.0"))
        #expect(GuidedProtocol.supportsPilot("garbage") == false)
        // La borne de guidage ne bouge pas.
        #expect(GuidedProtocol.supportsGuidance("0.9.24"))
    }
}
