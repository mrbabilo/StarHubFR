import Foundation
import Testing
@testable import StarHubTHCore

struct ProbeComparisonQualityTests {
    private func scope(_ pair: Int, frame: Double = 10, scene: [String: Int]? = ["animals": 10]) throws -> ProbeComparisonScope {
        let before = try (0..<5).map { try PerformanceFixture.minute(index: pair * 100 + $0, frame: 20) }
        let after = try (0..<5).map { try PerformanceFixture.minute(index: pair * 100 + 10 + $0, frame: frame, scene: scene) }
        let inventory = ["probe": ProbeInventoryEntry(modId: "mrbabilo.StarHubFR.Probe", version: "1", configSha: "aa")]
        return .make(before: PerformanceFixture.side("A\(pair)", minutes: before, inventory: inventory),
                     after: PerformanceFixture.side("B\(pair)", minutes: after, inventory: inventory))
    }

    @Test func sceneMissingOrChangedLimitsQuality() throws {
        let unknown = try scope(0, scene: nil)
        let metric = ProbeMetricComparison.compare(unknown, metric: .frameP50)
        let quality = ProbeComparisonQuality.assess(scope: unknown, metric: metric, repeats: [])
        #expect(quality.level == .limited && quality.reasons.contains(.sceneUnknown))
        let changed = try scope(1, scene: ["animals": 30])
        #expect(ProbeComparisonQuality.assess(scope: changed, metric: .compareForTest(changed), repeats: []).reasons.contains(.sceneChanged))
    }

    @Test func sceneZeroAndMissingAreDistinct() throws {
        let zero = try (0..<5).map { try PerformanceFixture.minute(index: $0, scene: ["animals": 0]) }
        let eight = try (0..<5).map { try PerformanceFixture.minute(index: $0, scene: ["animals": 8]) }
        if case .different(let differences) = ProbeScene.assess(before: zero, after: eight) {
            #expect(differences.first?.delta == 8 && differences.first?.percent == nil)
        } else { Issue.record("Zero to eight must describe a scene change") }
        #expect(ProbeScene.assess(before: Array(zero.prefix(4)), after: eight) == .unknown)
        #expect(ProbeScene.assess(before: eight, after: eight) == .similar)
    }

    @Test func repeatedNeedsThreeIndependentPairsAndNoOppositeResult() throws {
        let a = try scope(0), b = try scope(1), c = try scope(2)
        let metric = ProbeMetricComparison.compare(a, metric: .frameP50)
        #expect(ProbeComparisonQuality.assess(scope: a, metric: metric, repeats: [a, b, c]).level == .repeated)
        #expect(ProbeComparisonQuality.assess(scope: a, metric: metric, repeats: [a, a, a]).level == .usable)
        let opposite = try scope(3, frame: 40)
        #expect(ProbeComparisonQuality.assess(scope: a, metric: metric, repeats: [a, b, opposite]).level != .repeated)
    }
}

private extension ProbeMetricResult {
    static func compareForTest(_ scope: ProbeComparisonScope) -> Self {
        ProbeMetricComparison.compare(scope, metric: .frameP50)
    }
}
