import Foundation
import Testing
@testable import StarHubTHCore

struct ModImpactSampleTests {
    private func realSide() throws -> ProbeSide {
        let sessions = ProbeSessions.decode(timings: try Fixture.data("impact-timings.jsonl"),
                                            costs: try Fixture.data("impact-mod-costs.jsonl"))
        let inventory = ProbeInventory.decode(try Fixture.data("impact-inventory.jsonl"))
        let sides = ProbePerformance.sides(sessions: sessions, launches: inventory.launches,
                                           changes: inventory.changes, measurements: [])
        return try #require(sides.first { $0.comparable.kept.count >= ModImpactSources.minimumKeptMinutes })
    }

    /// Parts contre les totaux de la source, sonde exclue, version de l'inventaire du segment.
    @Test func inGameSamplesShareTheSourceTotalsWithoutTheProbe() throws {
        let side = try realSide()
        let source = try #require(ModImpactSources.inGame(side))
        #expect(source.kind == .inGame && source.id == side.id)
        #expect(!source.samples.keys.contains { $0.caseInsensitiveCompare(BenchmarkSides.probeId) == .orderedSame })
        #expect(source.probeMsPerFrame != nil)
        let samples = Array(source.samples.values)
        #expect(abs(samples.compactMap(\.fpsShare).reduce(0, +) - 1) < 1e-9)
        #expect(abs(samples.compactMap(\.allocShare).reduce(0, +) - 1) < 1e-9)
        #expect(samples.compactMap(\.spikeShare).max() == 1)
        let cp = try #require(source.samples["Pathoschild.ContentPatcher"])
        let inventoried = side.inventory?.values.first {
            $0.modId.caseInsensitiveCompare("Pathoschild.ContentPatcher") == .orderedSame }
        #expect(cp.version != nil && cp.version == inventoried?.version)
        let costs = ProbeCosts.segmentCosts(side.comparable.kept, costs: side.costs)
        #expect(abs(try #require(cp.msPerFrame) - (try #require(cp.msPerSecond)) / costs.fps) < 1e-9)
    }

    @Test func aShortSegmentIsNotASource() throws {
        let sessions = ProbeSessions.decode(timings: try Fixture.data("timings.jsonl"),
                                            costs: try Fixture.data("mod-costs.jsonl"))
        let inventory = ProbeInventory.decode(try Fixture.data("inventory.jsonl"))
        let sides = ProbePerformance.sides(sessions: sessions, launches: inventory.launches,
                                           changes: inventory.changes, measurements: [])
        #expect(!sides.isEmpty)
        #expect(sides.allSatisfy { ModImpactSources.inGame($0) == nil })   // 4 minutes au plus
    }

    @Test func launchesNeedProbe090CompleteWarmAndProbeFirst() throws {
        let records = ProbeLoadRecords.decode(try Fixture.data("loads-load.jsonl")).records
        let first = try #require(records.first { $0.probeLoadsFirst == true })
        let notFirst = try #require(records.first { $0.probeLoadsFirst == false })
        let source = try #require(ModImpactSources.load(first, launches: [], isCold: false))
        #expect(source.kind == .launch && source.id == first.id)
        #expect(abs(source.samples.values.compactMap(\.loadShare).reduce(0, +) - 1) < 1e-9)
        #expect(source.samples.values.allSatisfy { $0.version == nil })   // pas d'inventaire passé
        #expect(ModImpactSources.load(first, launches: [], isCold: true) == nil)
        #expect(ModImpactSources.load(notFirst, launches: [], isCold: false) == nil)
        let older = ProbeLoadRecords.decode(try Fixture.data("loads-entry.jsonl")).records   // 0.8.0
        #expect(older.allSatisfy { ModImpactSources.load($0, launches: [], isCold: false) == nil })
        let saves = ProbeLoadRecords.decode(try Fixture.data("loads.jsonl")).records.filter { $0.kind == .save }
        #expect(saves.allSatisfy { ModImpactSources.load($0, launches: [], isCold: false) == nil })   // < 0.9.0
    }

    @Test func aSampleUnderEveryFloorIsNegligible() {
        func s(fps: Double?, spike: Double?, alloc: Double?, load: Double?) -> ModImpactSample {
            ModImpactSample(sourceId: "x", kind: .inGame, date: Date(timeIntervalSince1970: 0), version: nil,
                            msPerSecond: nil, maxMs: nil, allocMBPerMinute: nil, msPerFrame: nil,
                            frameWorkShare: nil, patchesMeasured: nil, ms: nil,
                            fpsShare: fps, spikeShare: spike, allocShare: alloc, loadShare: load)
        }
        #expect(s(fps: 0.0009, spike: 0.009, alloc: 0.0005, load: nil).isNegligible)
        #expect(!s(fps: 0.0009, spike: 0.02, alloc: 0.0005, load: nil).isNegligible)   // un pic suffit
        #expect(!s(fps: nil, spike: nil, alloc: nil, load: 0.001).isNegligible)       // au plancher : compte
        #expect(s(fps: nil, spike: nil, alloc: nil, load: nil).isNegligible)
    }
}
