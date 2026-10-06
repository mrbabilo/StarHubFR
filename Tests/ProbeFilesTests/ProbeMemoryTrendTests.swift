import Foundation
import Testing
@testable import StarHubTHCore

struct ProbeMemoryTrendTests {
    private func series(_ count: Int) throws -> [ProbeComparableMinute] {
        try (0..<count).map {
            ProbeComparableMinute(minute: try PerformanceFixture.minute(index: $0, memory: 100 + Double($0) * 10), patchesMeasured: false)
        }
    }

    @Test func slopeUsesElapsedTimeAndRobustEndpoints() throws {
        let result = try #require(ProbeMemoryTrend.analyze(series(10), excludedAt: []).first)
        #expect(result.slopeMBPerMinute == 10 && result.deltaMB == 70 && result.count == 10)
        #expect(try ProbeMemoryTrend.analyze(series(9), excludedAt: []).first?.slopeMBPerMinute == nil)
    }

    @Test func exclusionsAndGapsBreakTrends() throws {
        let minutes = try series(20)
        let split = ProbeMemoryTrend.analyze(minutes, excludedAt: [Date(timeIntervalSince1970: 570)])
        #expect(split.map(\.count) == [10, 10])
        #expect(ProbeMemoryTrend.analyze(Array(minutes.prefix(9)) + Array(minutes.suffix(9)), excludedAt: []).map(\.count) == [9, 9])
    }

    @Test func longSeriesKeepsEndpointsAndAnnouncesSampling() throws {
        let result = try #require(ProbeMemoryTrend.analyze(series(301), excludedAt: []).first)
        #expect(result.sampled && result.count == 301)
        #expect(result.slopeMBPerMinute == 10 && result.deltaMB == 2980)
    }

    @Test func duplicateTimestampKeepsLastValidObservation() throws {
        let original = try series(10)
        let duplicate = ProbeComparableMinute(minute: try PerformanceFixture.minute(index: 9, memory: 190), patchesMeasured: false)
        let result = try #require(ProbeMemoryTrend.analyze(original + [duplicate], excludedAt: []).first)
        #expect(result.count == 10 && result.slopeMBPerMinute == 10)
    }
}
