import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct BenchmarkVerdictTests {
    static func record(_ run: String?, _ kind: ProbeLoadRecord.Kind, total: Double,
                       complete: Bool = true, patches: Bool = false) -> ProbeLoadRecord {
        let last = kind == .launch ? "L4" : "S9"
        return ProbeLoadRecord(
            kind: kind, session: run ?? "manual", atText: "2026-09-30T20:00:00+02:00", at: nil,
            probeVersion: "0.7.0", complete: complete, reload: false,
            saveName: kind == .save ? "S_bench" : nil, patchesMeasured: patches,
            saveBytes: nil, saveDate: nil,
            milestones: [ProbeLoadMilestone(name: kind == .launch ? "L0" : "S0", ms: 0),
                         ProbeLoadMilestone(name: last, ms: total)],
            phases: [], final: nil,
            health: .init(packSeam: "ok", assetHook: "ok", loadHook: "ok", offThreadSections: 0),
            benchmarkRun: run)
    }

    static let runs = [BenchmarkRun(id: "w", side: .warmupA), BenchmarkRun(id: "wb", side: .warmupB),
                       BenchmarkRun(id: "a1", side: .a), BenchmarkRun(id: "b1", side: .b),
                       BenchmarkRun(id: "a2", side: .a), BenchmarkRun(id: "b2", side: .b)]

    static func both(_ run: String, launch: Double, save: Double, complete: Bool = true) -> [ProbeLoadRecord] {
        [record(run, .launch, total: launch), record(run, .save, total: save, complete: complete)]
    }

    @Test func warmupsAndManualLinesAreIgnored() throws {
        let records = Self.both("w", launch: 500_000, save: 500_000) + Self.both("wb", launch: 1, save: 1)
            + Self.both("a1", launch: 100_000, save: 90_000) + Self.both("a2", launch: 101_000, save: 91_000)
            + Self.both("b1", launch: 80_000, save: 70_000) + Self.both("b2", launch: 80_500, save: 70_500)
            + [Self.record(nil, .launch, total: 1)]
        let outcome = BenchmarkVerdict.evaluate(records: records, runs: Self.runs, sameSave: true)
        guard case .result(let launch) = outcome.launch else { Issue.record("\(outcome.launch)"); return }
        #expect(launch.medianAMs == 100_500 && launch.medianBMs == 80_250)
        #expect(launch.verdict.isDecided)
        guard case .result(let save) = outcome.save else { Issue.record("\(outcome.save)"); return }
        #expect(save.medianAMs == 90_500)
    }

    @Test func differentSavesMakeTheLoadNotComparable() {
        let records = Self.both("a1", launch: 100_000, save: 90_000) + Self.both("a2", launch: 101_000, save: 91_000)
            + Self.both("b1", launch: 80_000, save: 70_000) + Self.both("b2", launch: 80_500, save: 70_500)
        let outcome = BenchmarkVerdict.evaluate(records: records, runs: Self.runs, sameSave: false)
        #expect(outcome.save == .notComparable)
        if case .notComparable = outcome.launch { Issue.record("le lancement reste comparable") }
    }

    @Test func incompleteLoadsAreDroppedAndMixedPatchesAreNotComparable() {
        var records = Self.both("a1", launch: 100_000, save: 90_000) + Self.both("a2", launch: 101_000, save: 91_000)
            + Self.both("b1", launch: 80_000, save: 70_000) + Self.both("b2", launch: 80_500, save: 70_500, complete: false)
        var outcome = BenchmarkVerdict.evaluate(records: records, runs: Self.runs, sameSave: true)
        guard case .result(let save) = outcome.save else { Issue.record("\(outcome.save)"); return }
        #expect(save.verdict == .grayZone(beforeCount: 2, afterCount: 1))
        records.append(Self.record("b1", .launch, total: 80_000, patches: true))
        outcome = BenchmarkVerdict.evaluate(records: records, runs: Self.runs, sameSave: true)
        #expect(outcome.launch == .notComparable)
    }

    /// Review Focus 3 : un lancement sans ligne `save` complète est un échec.
    @Test func aRunSucceedsOnlyWithACompleteSaveLine() {
        let records = [Self.record("a1", .launch, total: 1), Self.record("a2", .save, total: 1, complete: false),
                       Self.record("b1", .save, total: 1)]
        #expect(!BenchmarkVerdict.hasCompleteSave(records, runId: "a1"))
        #expect(!BenchmarkVerdict.hasCompleteSave(records, runId: "a2"))
        #expect(BenchmarkVerdict.hasCompleteSave(records, runId: "b1"))
    }
}
