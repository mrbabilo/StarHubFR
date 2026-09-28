import Testing
import Foundation
@testable import StarHubTHCore

struct ProbeComparisonTests {
    /// Une minute gardée où tout est constant sauf `FrameInterval.P50` (et
    /// `Update.P50` quand on le demande).
    private func item(hour: Int, index: Int, p50: Double, updateP50: Double = 5) -> ProbeComparableMinute {
        let json = """
        {"Session":"s","At":"2026-09-28T\(hour):0\(index):00.0000000+02:00","WallSeconds":60,
         "Fps":\(1000.0 / p50),
         "FrameInterval":{"Count":45,"Avg":\(p50),"P50":\(p50),"P99":\(p50 * 1.5),"Max":\(p50 * 2)},
         "Update":{"Count":60,"Avg":\(updateP50),"P50":\(updateP50),"P99":\(updateP50 + 4),"Max":\(updateP50 + 5)},
         "Draw":{"Count":45,"Avg":4,"P50":4,"P99":8,"Max":9},
         "HeapMB":4000,"LoadedMods":289,"Location":"Farm","MenuTicks":0,
         "Tick":{"Count":60,"Avg":20,"P50":20,"P99":40,"Max":50},"GameTime":650}
        """
        return ProbeComparableMinute(
            minute: try! ProbeJSON.decoder().decode(ProbeMinute.self, from: Data(json.utf8)),
            patchesMeasured: false)
    }

    private func side(_ frameP50: Double, count: Int = 5, updateP50: Double = 5) -> [ProbeComparableMinute] {
        (0..<count).map { item(hour: 10, index: $0, p50: frameP50, updateP50: updateP50) }
    }

    /// Variante avec des P50 explicites (pour viser les quartiles).
    private func sideWithP50s(_ p50s: [Double]) -> [ProbeComparableMinute] {
        p50s.enumerated().map { item(hour: 11, index: $0, p50: $1) }
    }

    @Test func netChangeIsDetected() {
        let result = ProbeComparison.compare(side(30), side(36))
        #expect(result.frameP50.verdict == .netChange(delta: 6, percent: 20))
        #expect(result.verdict == .netChange(delta: 6, percent: 20))
        #expect(!result.vsyncLimited)
    }

    @Test func smallChangeIsNoise() {
        let result = ProbeComparison.compare(side(30), side(30.5))
        #expect(result.frameP50.verdict == .noise)
    }

    /// Chevauchement au point près : `q3A == q1B` n'est **pas** disjoint —
    /// bruit, même avec un écart médian > 5 %.
    @Test func touchingQuartilesAreNoise() {
        let a = side(30)                                     // Q1 = Q3 = 30
        let b = sideWithP50s([30, 30, 32, 34, 34])           // Q1 = 30, médiane 32
        let result = ProbeComparison.compare(a, b)
        #expect(result.frameP50.a.q3 == 30 && result.frameP50.b.q1 == 30)
        #expect(result.frameP50.verdict == .noise)
    }

    @Test func tooFewMinutesIsNotEnoughData() {
        let result = ProbeComparison.compare(side(30, count: 4), side(36))
        #expect(result.frameP50.verdict == .notEnoughData)
        #expect(result.verdict == .notEnoughData)
    }

    /// Garde patches : états connus qui diffèrent, ou un seul côté renseigné.
    @Test func asymmetricPatchStateBlocksComparison() {
        let off = side(30)
        let on = side(36).map { ProbeComparableMinute(minute: $0.minute, patchesMeasured: true) }
        let mismatch = ProbeComparison.compare(off, on)
        #expect(mismatch.patchesMismatch)
        #expect(mismatch.verdict == .notEnoughData)
        let unknown = side(30).map { ProbeComparableMinute(minute: $0.minute, patchesMeasured: nil) }
        #expect(ProbeComparison.compare(unknown, on).patchesMismatch)
        // Deux inconnus s'accordent (fixture sans coûts : nil partout).
        #expect(!ProbeComparison.compare(unknown, unknown).patchesMismatch)
    }

    /// Plafond de synchro : les deux médianes à 16,7 ms ± 0,3 → le verdict de
    /// tête passe au travail de trame (Update.P50 + Draw.P50 = 9 ms ici).
    @Test func vsyncCeilingSwitchesToFrameWork() {
        let result = ProbeComparison.compare(side(16.5), side(16.9))
        // Travail de trame identique des deux côtés : bruit, pas un écart de trame.
        #expect(result.vsyncLimited)
        #expect(result.verdict == .noise)
    }

    @Test func vsyncCeilingStillShowsRealWorkChange() {
        // Côté B : Update.P50 8 au lieu de 5 → travail 12 contre 9.
        let result = ProbeComparison.compare(side(16.5), side(16.5, updateP50: 8))
        #expect(result.vsyncLimited)
        #expect(result.verdict == .netChange(delta: 3, percent: 33.3))
    }
}
