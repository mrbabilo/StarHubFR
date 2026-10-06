import Foundation
import Testing
@testable import StarHubTHCore

struct ProbeComparisonScopeTests {
    @Test func missingInventoryNeverBecomesNoChanges() {
        let scope = ProbeComparisonScope.make(before: PerformanceFixture.side("A", inventory: nil),
                                              after: PerformanceFixture.side("B"))
        #expect(scope.diff == nil)
        #expect(scope.issues.contains(.inventoryMissing))
    }

    @Test func overlapUsesHalfOpenWindowsAndSharedMinutes() throws {
        let a = PerformanceFixture.side("A", session: "s", start: 0, end: 600)
        let overlapping = PerformanceFixture.side("B", session: "s", start: 300, end: 900)
        let adjacent = PerformanceFixture.side("C", session: "s", start: 600, end: 900)
        #expect(ProbeComparisonScope.make(before: a, after: overlapping).issues.contains(.overlappingWindows))
        #expect(!ProbeComparisonScope.make(before: a, after: adjacent).issues.contains(.overlappingWindows))
        #expect(ProbeComparisonScope.make(before: a, after: a).issues.contains(.sameSelection))
        let minute = try PerformanceFixture.minute(index: 1)
        let x = PerformanceFixture.side("X", session: "s", minutes: [minute])
        let y = PerformanceFixture.side("Y", session: "s", minutes: [minute])
        #expect(ProbeComparisonScope.make(before: x, after: y).issues.contains(.overlappingWindows))
    }

    @Test func mixedAndPartlyUnknownOptionsCannotDisappear() throws {
        let minutes = try (0..<2).map { try PerformanceFixture.minute(index: $0) }
        let known = PerformanceFixture.side("A", minutes: minutes)
        let mixed = PerformanceFixture.side("B", minutes: minutes, patches: [true, false])
        let unknown = PerformanceFixture.side("C", minutes: minutes, patches: [false, nil])
        #expect(ProbeComparisonScope.make(before: known, after: mixed).issues.contains(.patchesMixed))
        #expect(ProbeComparisonScope.make(before: known, after: unknown).issues.contains(.patchesUnknown))
        #expect(ProbeComparisonScope.make(before: known, after: unknown).issues.contains(.patchesDiffer))
    }
}
