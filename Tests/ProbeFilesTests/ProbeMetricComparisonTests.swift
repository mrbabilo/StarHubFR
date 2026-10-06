import Testing
@testable import StarHubTHCore

struct ProbeMetricComparisonTests {
    private func side(_ id: String, farm: [Double], town: [Double] = []) throws -> ProbeSide {
        let farmMinutes = try farm.enumerated().map {
            try PerformanceFixture.minute(index: $0.offset, session: id, frame: $0.element)
        }
        let townMinutes = try town.enumerated().map {
            try PerformanceFixture.minute(index: farm.count + $0.offset, session: id, location: "Town", frame: $0.element)
        }
        return PerformanceFixture.side(id, minutes: farmMinutes + townMinutes)
    }

    @Test func locationBalanceDoesNotInventAnImprovement() throws {
        let a = try side("A", farm: Array(repeating: 20, count: 20), town: Array(repeating: 40, count: 5))
        let b = try side("B", farm: Array(repeating: 20, count: 5), town: Array(repeating: 40, count: 20))
        let result = ProbeMetricComparison.compare(.make(before: a, after: b), metric: .frameP50)
        #expect(result.before == 30 && result.after == 30)
        #expect(result.outcome == .noClearDifference)
    }

    @Test func oppositeLocationsAreNotAStableGlobalResult() throws {
        let a = try side("A", farm: Array(repeating: 20, count: 5), town: Array(repeating: 20, count: 5))
        let b = try side("B", farm: Array(repeating: 10, count: 5), town: Array(repeating: 30, count: 5))
        #expect(ProbeMetricComparison.compare(.make(before: a, after: b), metric: .frameP50).outcome == .mixedLocations)
    }

    @Test func insufficientUnmatchedAndMissingRemainDistinct() throws {
        let a = try side("A", farm: [20, 20, 20, 20])
        let b = try side("B", farm: [30, 30, 30, 30])
        #expect(ProbeMetricComparison.compare(.make(before: a, after: b), metric: .frameP50).outcome == .insufficient)
        let town = try side("C", farm: [], town: [30, 30, 30, 30, 30])
        #expect(ProbeMetricComparison.compare(.make(before: a, after: town), metric: .frameP50).outcome == .incomparable)
        #expect(ProbeMetricComparison.compare(.make(before: a, after: b), metric: .committed).outcome == .unavailable)
    }

    @Test func exactThresholdIsNeutralAndOverlappingRangesAreVariable() throws {
        let a = try side("A", farm: [20, 20, 20, 20, 20])
        let b = try side("B", farm: [21, 21, 21, 21, 21])
        #expect(ProbeMetricComparison.compare(.make(before: a, after: b), metric: .frameP50).outcome == .noClearDifference)
        let c = try side("C", farm: [10, 20, 25, 30, 40])
        #expect(ProbeMetricComparison.compare(.make(before: a, after: c), metric: .frameP50).outcome == .variable)
    }

    @Test func memoryZeroBaselineIsNeutralWithNoPercentage() throws {
        let a = PerformanceFixture.side("A", minutes: try (0..<5).map { try PerformanceFixture.minute(index: $0, memory: 0) })
        let b = PerformanceFixture.side("B", minutes: try (0..<5).map { try PerformanceFixture.minute(index: $0, memory: 10) })
        let result = ProbeMetricComparison.compare(.make(before: a, after: b), metric: .workingSet)
        #expect(result.outcome == .memoryChanged)
        #expect(result.delta == 10 && result.percent == nil)
    }

    @Test func invalidValuesAreRejectedBeforeAggregation() {
        #expect(ProbeMetric.frameP50.validated(-1) == nil)
        #expect(ProbeMetric.frameP50.validated(0) == nil)
        #expect(ProbeMetric.workingSet.validated(.nan) == nil)
        #expect(ProbeMetric.workingSet.validated(.infinity) == nil)
        #expect(ProbeMetric.workingSet.validated(0) == 0)
    }
}
