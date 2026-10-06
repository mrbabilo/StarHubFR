import Foundation
import Testing
@testable import StarHubTHCore

struct ProbeReviewRegressionTests {
    @Test func concurrentDatesPreserveFractionsAndTimeZones() async {
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<200 {
                group.addTask {
                    let fraction = index.isMultiple(of: 2)
                    let text = fraction ? "2026-10-06T10:00:00.1234567+02:00" : "2026-10-06T08:00:00Z"
                    let expected = Date(timeIntervalSince1970: 1_791_273_600 + (fraction ? 0.123 : 0))
                    let parsed = ProbeDate.parse(text)
                    #expect(parsed.map { abs($0.timeIntervalSince(expected)) < 0.000_01 } == true)
                    #expect(ProbeDate.parse("invalid date") == nil)
                }
            }
        }
    }

    @Test func oppositeEvidenceInOneLocationPreventsRepeatedQuality() throws {
        func scope(_ pair: Int, farm: Double = 10, town: Double = 10) throws -> ProbeComparisonScope {
            let inventory = ["probe": ProbeInventoryEntry(modId: "mrbabilo.StarHubFR.Probe", version: "1", configSha: "aa")]
            let a = try (0..<10).map { try PerformanceFixture.minute(index: pair * 100 + $0, location: $0 < 5 ? "Farm" : "Town", frame: 20) }
            let b = try (0..<10).map { try PerformanceFixture.minute(index: pair * 100 + 20 + $0, location: $0 < 5 ? "Farm" : "Town", frame: $0 < 5 ? farm : town) }
            return .make(before: PerformanceFixture.side("A\(pair)", minutes: a, inventory: inventory),
                         after: PerformanceFixture.side("B\(pair)", minutes: b, inventory: inventory))
        }
        let first = try scope(0)
        let others = try [scope(1), scope(2), scope(3, farm: 30, town: 20)]
        let result = ProbeComparisonQuality.assess(scope: first, metric: ProbeMetricComparison.compare(first, metric: .frameP50), repeats: others)
        #expect(result.level != .repeated)
        #expect(result.reasons.contains(.conflictingRepeats))
    }

    @Test func missingSharedMetricCannotBorrowFromUnmatchedLocation() throws {
        let before = try (0..<5).map { try PerformanceFixture.minute(index: $0, memory: nil) }
            + (5..<10).map { try PerformanceFixture.minute(index: $0, location: "Town", memory: 100) }
        let after = try (0..<5).map { try PerformanceFixture.minute(index: $0, memory: 50) }
        let scope = ProbeComparisonScope.make(before: PerformanceFixture.side("A", minutes: before), after: PerformanceFixture.side("B", minutes: after))
        let result = ProbeMetricComparison.compare(scope, metric: .workingSet)
        #expect(result.before == nil && result.delta == nil && result.percent == nil)
        #expect(result.outcome == .unavailable)
    }

    @MainActor @Test func latestSessionIncludesGameplayAfterGuidedWindow() async throws {
        let minutes = try (0..<30).map { try PerformanceFixture.minute(index: $0) }
        let whole = PerformanceFixture.side("whole", session: "session", start: 0, end: 1800, minutes: minutes)
        let window = Array(minutes[5..<10])
        let measurement = ProbeMeasurement(name: "guided", start: Date(timeIntervalSince1970: 300), end: Date(timeIntervalSince1970: 600))
        let guided = ProbeSide(id: "guided", kind: .measurement(measurement, crossedChangeAt: nil), session: "session",
            start: measurement.start, end: measurement.end, minutes: window, costs: [], inventory: [:],
            comparable: PerformanceFixture.side("x", minutes: window).comparable)
        let store = ProbePerformanceStore(loader: { _ in ProbePerformanceSnapshot(sides: [whole, guided]) })
        await store.reload()
        #expect(store.singleSummary?.metrics[.frameP50]?.count == 30)
    }

    @Test func perModMissingCostIsNotAnAddedCostOrEvidence() throws {
        let minutes = try (0..<5).map { try PerformanceFixture.minute(index: $0) }
        func cost(_ at: String, includeChanged: Bool) throws -> ProbeModCostMinute {
            let ids = includeChanged ? ["Common", "Changed"] : ["Common"]
            let mods = ids.map { id in
                ["Mod": id, "SelfMs": 60, "MsPerSecond": 1, "MaxMs": 1, "AllocKB": 0, "Calls": 1, "Events": []] as [String: Any]
            }
            let json: [String: Any] = ["Session": "s", "At": at, "WallSeconds": 60, "Frames": 3000, "Mods": mods]
            return try ProbeJSON.decoder().decode(ProbeModCostMinute.self, from: JSONSerialization.data(withJSONObject: json))
        }
        func side(_ id: String, after: Bool) throws -> ProbeSide {
            let base = PerformanceFixture.side(id, minutes: minutes)
            return ProbeSide(id: id, kind: .segment, session: id, start: nil, end: nil, minutes: minutes,
                costs: try minutes.map { try cost($0.at, includeChanged: after) },
                inventory: ["Changed": ProbeInventoryEntry(modId: "Changed", version: after ? "2" : "1", configSha: "aa")],
                comparable: base.comparable)
        }
        let report = try ProbePerformance.report(before: side("A", after: false), after: side("B", after: true))
        #expect(!report.costDeltas.contains { $0.modId == "Changed" })
        #expect(!report.analysis.evidence.contains { if case .directCost(let id, _) = $0 { return id == "Changed" }; return false })
    }
}
