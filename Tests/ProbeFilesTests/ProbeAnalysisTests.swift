import Foundation
import Testing
@testable import StarHubTHCore

struct ProbeAnalysisTests {
    private var probe: ProbeInventoryEntry { ProbeInventoryEntry(modId: "mrbabilo.StarHubFR.Probe", version: "1", configSha: "aa") }
    private func report(frame: Double = 30, count: Int = 5, scene: [String: Int]? = ["animals": 10],
                        missingInventory: Bool = false, added: [String] = [], repeated: Bool = false) throws -> ProbePerformanceReport {
        func scope(_ pair: Int) throws -> ProbeComparisonScope {
            let a = try (0..<count).map { try PerformanceFixture.minute(index: pair * 100 + $0, frame: 20) }
            let b = try (0..<count).map { try PerformanceFixture.minute(index: pair * 100 + 20 + $0, frame: frame, scene: scene) }
            var inventory = ["probe": probe]
            for id in added { inventory[id] = ProbeInventoryEntry(modId: id, version: "1", configSha: "aa") }
            return .make(before: PerformanceFixture.side("A\(pair)", minutes: a, inventory: missingInventory ? nil : ["probe": probe]),
                         after: PerformanceFixture.side("B\(pair)", minutes: b, inventory: inventory))
        }
        let pair = try scope(0)
        return try ProbePerformance.report(before: pair.before, after: pair.after,
                                           repeats: repeated ? [scope(1), scope(2)] : [])
    }

    @Test func directionComesFromBalancedFrameMetric() throws {
        #expect(try report().analysis.direction == .slower(percent: 50))
        #expect(try report(frame: 10).analysis.direction == .faster(percent: 50))
        #expect(try report(frame: 20).analysis.direction == .noDifference)
        #expect(try report(count: 3).analysis.direction == .inconclusive)
    }

    @Test func onePairNeverHasRepeatedConfidence() throws {
        #expect(try report(count: 30).analysis.confidence == .medium)
        #expect(try report(repeated: true).analysis.confidence == .high)
        #expect(try report(scene: nil).analysis.confidence == .low)
    }

    @Test func missingInventoryPreventsAttributionAndZeroCostClaims() throws {
        let result = try report(frame: 20, missingInventory: true, added: ["Mod.A"]).analysis
        #expect(result.confidence == .low)
        #expect(!result.evidence.contains(.singleChange(modId: "Mod.A")))
        #expect(result.recommendation == .rerunCleanMeasurement(location: "Farm", missingMinutes: 0))
    }

    @Test func singleChangeIsALeadToRepeatBeforeActing() throws {
        let result = try report(added: ["Mod.A"]).analysis
        #expect(result.evidence.contains(.singleChange(modId: "Mod.A")))
        #expect(result.recommendation == .rerunCleanMeasurement(location: "Farm", missingMinutes: 0))
        #expect(try report(added: ["Mod.A"], repeated: true).analysis.recommendation == .disableMod(modId: "Mod.A"))
    }

    @Test func multipleChangesNeedIsolationAndNoDifferenceNeverMeansNoCost() throws {
        #expect(try report(added: ["Mod.A", "Mod.B"]).analysis.recommendation == .isolate)
        #expect(try report(frame: 20, added: ["Mod.A"]).analysis.recommendation == .keep)
        #expect(try report(frame: 21).analysis.recommendation == .keep)
    }

    @Test func missingMinutesAreCountedToFiveInTheSelectedPlace() throws {
        #expect(try report(count: 3).analysis.recommendation == .rerunCleanMeasurement(location: "Farm", missingMinutes: 2))
    }

    @Test func directEvidenceNeverBecomesAnIndirectPercentage() throws {
        let r = try report(added: ["Mod.A", "Mod.B"])
        let input = ProbeAnalysisInput(comparison: r.comparison, diff: r.diff, costDeltas: [
            ProbeCostDelta(modId: "Unchanged", msPerSecondA: 0, msPerSecondB: 9, presence: .both),
            ProbeCostDelta(modId: "Mod.B", msPerSecondA: 0, msPerSecondB: 1, presence: .both),
            ProbeCostDelta(modId: "mod.a", msPerSecondA: 0, msPerSecondB: 2, presence: .both)],
            exclusionsA: [.menuOpen: 3], exclusionsB: [:], locationsRestricted: true, measurement: nil,
            dominantLocation: "Farm", metrics: r.metrics, quality: r.quality)
        let result = ProbeAnalysis.analyze(input)
        let direct = result.evidence.compactMap { item -> String? in
            if case .directCost(let id, _) = item { return id }; return nil
        }
        #expect(direct == ["mod.a", "Mod.B"])
        #expect(!result.evidence.contains { if case .indirectShare = $0 { return true }; return false })
        #expect(result.evidence.contains(.excludedMinutes(a: [.menuOpen: 3], b: [:])))
    }

    @Test func incompatibleOptionsPreventConclusions() throws {
        let minutes = try (0..<5).map { try PerformanceFixture.minute(index: $0) }
        let a = PerformanceFixture.side("A", minutes: minutes)
        let b = PerformanceFixture.side("B", minutes: minutes, patches: Array(repeating: true, count: 5))
        let result = ProbePerformance.report(before: a, after: b)
        #expect(result.analysis.direction == .inconclusive && result.analysis.confidence == .low)
    }
}
