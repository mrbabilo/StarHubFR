import Testing
@testable import StarHubTHCore

struct ProbePerformanceSummaryTests {
    @Test func singleSessionHasMeasurementsWithoutInventedComparison() throws {
        let side = PerformanceFixture.side("A", minutes: try (0..<10).map { try PerformanceFixture.minute(index: $0) })
        let summary = ProbePerformanceSummary.single(side)
        #expect(summary.metrics[.frameP50]?.median == 20)
        #expect(summary.metrics[.workingSet]?.median == 100)
        #expect(summary.metrics[.committed]?.median == nil)
        #expect(summary.memory.count == 1)
    }

    @Test func defaultPairDoesNotCompareASegmentWithItsOwnMeasurement() throws {
        let minutes = try (0..<10).map { try PerformanceFixture.minute(index: $0) }
        let a = PerformanceFixture.side("A", session: "same", minutes: minutes)
        let b = PerformanceFixture.side("B", session: "same", minutes: minutes)
        #expect(ProbePerformance.defaultPair([a, b]) == nil)
    }
}
