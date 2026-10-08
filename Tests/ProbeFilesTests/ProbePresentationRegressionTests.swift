import Foundation
import Testing
@testable import StarHubTHCore

struct ProbePresentationRegressionTests {
    @Test func timelineUsesSelectedMetricAndBreaksAcrossMissingMinute() throws {
        let a = PerformanceFixture.side("A", minutes: try [0, 1, 2, 4, 5, 6].map {
            try PerformanceFixture.minute(index: $0, frame: 20, memory: 500)
        })
        let b = PerformanceFixture.side("B", minutes: try (0..<6).map { try PerformanceFixture.minute(index: $0, memory: 600) })
        let report = ProbePerformance.report(before: a, after: b)
        let timeline = ProbeComparisonChart.timeline(report, measure: .workingSet)
        let before = timeline.marks.filter { $0.side == .before }
        #expect(before.compactMap(\.value) == Array(repeating: 500, count: 6))
        #expect(before[2].segmentId != before[3].segmentId)
        #expect(timeline.yMax == 600)
        #expect(Set(timeline.marks.map(\.id)).count == 12)
    }

    @Test func unmatchedLocationIsExplainedWithoutPlottingZero() throws {
        let common = try (0..<5).map { try PerformanceFixture.minute(index: $0) }
        let town = try PerformanceFixture.minute(index: 6, location: "Town")
        let report = ProbePerformance.report(before: PerformanceFixture.side("A", minutes: common + [town]),
                                             after: PerformanceFixture.side("B", minutes: common))
        let mark = try #require(ProbeComparisonChart.timeline(report, measure: .frameP50).marks.first { $0.location == "Town" })
        #expect(mark.value == nil && mark.exclusion == .unmatchedLocation)
    }

    @Test func invalidLoadingDurationsCannotBecomeAnImprovement() {
        #expect(ProbeLoadComparison.verdict(before: [100, 100], after: [-1, -1]) == .grayZone(beforeCount: 2, afterCount: 0))
        #expect(ProbeLoadComparison.verdict(before: [.nan, 100], after: [50, 50]) == .grayZone(beforeCount: 1, afterCount: 2))
    }

    @Test func historicalRankingUsesAbsoluteValuesAndMarksUnknowns() {
        func entry(_ id: String, frame: Double?, share: Double, version: String = "1") -> ModImpactEntry {
            let stats = ModImpactVersionStats(version: version, shares: [.fps: share], ranges: [:],
                sourceCount: 3, inGameSources: 3, launchSources: 0, saveSources: 0, patchedSources: 0,
                first: .distantPast, last: .distantPast, msPerFrame: frame, frameWorkShare: nil,
                launchMs: nil, saveMs: nil, allocMBPerMinute: nil, textureMB: nil, textureSources: 0)
            return ModImpactEntry(id: id, modId: id, name: id, installedVersion: "2", isEnabled: true, versions: [stats])
        }
        let entries = [entry("A", frame: 2, share: 0.01), entry("B", frame: 1, share: 0.8), entry("C", frame: nil, share: 1)]
        let rows = ProbeImpactPresentation.rows(entries: entries, axis: .fps)
        #expect(rows.map(\.id) == ["A", "B", "C"])
        #expect(rows[0].value == 2 && !rows[0].currentVersionMeasured)
        #expect(rows[2].value == nil)
        #expect(ProbeImpactPresentation.rows(entries: entries, axis: .save).allSatisfy { $0.value == nil })
    }

    @Test func historicalCoverageCountsOnlySourcesThatMeasuredTheAxis() {
        func sample(_ id: String, frame: Double?, day: Double) -> ModImpactSample {
            ModImpactSample(sourceId: id, kind: .inGame, date: Date(timeIntervalSince1970: day * 86400),
                version: "1", msPerSecond: nil, maxMs: nil, allocMBPerMinute: nil, msPerFrame: frame,
                frameWorkShare: nil, patchesMeasured: false, ms: nil, fpsShare: frame.map { _ in 0.1 },
                spikeShare: nil, allocShare: nil, loadShare: nil, textureMB: nil)
        }
        let entry = ModImpactEntry(id: "A", modId: "A", name: "A", installedVersion: "1", isEnabled: true,
            versions: ModImpact.versionStats([sample("measured", frame: 2, day: 1), sample("missing", frame: nil, day: 2)]))
        let row = ProbeImpactPresentation.rows(entries: [entry], axis: .fps).first
        #expect(row?.sourceCount == 1)
        #expect(row?.lastMeasured == Date(timeIntervalSince1970: 86400))
    }
}
