import Foundation
import Testing
@testable import StarHubTHCore

struct ModImpactFormatTests {
    /// Virgule en français, point ailleurs (revue : virgule même en anglais).
    @Test func decimalSeparatorFollowsTheLanguage() {
        #expect(ModImpactFormat.number(1.25, digits: 2, language: "fr") == "1,25")
        #expect(ModImpactFormat.number(1.25, digits: 2, language: "en") == "1.25")
        #expect(ModImpactFormat.percent(0.123, language: "fr") == "12,3 %")
        #expect(ModImpactFormat.percent(0.0004, language: "en") == "0.04 %")
    }

    /// Sous la seconde, des millisecondes : « −0,0 s » pour 40 ms disait zéro.
    @Test func shortDurationsStayReadable() {
        #expect(ModImpactFormat.duration(40, language: "fr") == "40 ms")
        #expect(ModImpactFormat.duration(999, language: "en") == "999 ms")
        #expect(ModImpactFormat.duration(2_450, language: "fr") == "2,5 s")
        #expect(ModImpactFormat.duration(12_400, language: "en") == "12 s")
        #expect(ModImpactFormat.duration(110_000, language: "fr") == "1 min 50 s")
    }

    /// Un écart qui s'arrondit à 0 n'est ni un gain ni une perte.
    @Test func aRoundedZeroEvolutionIsStable() {
        #expect(ModImpactFormat.evolution(-0.4) == .stable)
        #expect(ModImpactFormat.evolution(0.49) == .stable)
        #expect(ModImpactFormat.evolution(-0.5) == .gain)
        #expect(ModImpactFormat.evolution(3) == .loss)
    }
}
