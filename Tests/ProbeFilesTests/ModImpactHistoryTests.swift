import Foundation
import Testing
@testable import StarHubTHCore

struct ModImpactHistoryTests {
    private func sample(_ source: String, day: Double, version: String? = "1.0", fps: Double = 0.2,
                        kind: ModImpactSample.Kind = .inGame) -> ModImpactSample {
        ModImpactSample(sourceId: source, kind: kind, date: Date(timeIntervalSince1970: day * 86_400),
                        version: version, msPerSecond: 1, maxMs: 1, allocMBPerMinute: 1, msPerFrame: 0.1,
                        frameWorkShare: 0.01, patchesMeasured: true, ms: nil,
                        fpsShare: fps, spikeShare: 0.5, allocShare: 0.1, loadShare: nil)
    }
    private func source(_ id: String, day: Double, _ samples: [String: ModImpactSample]) -> ModImpactSource {
        ModImpactSource(id: id, kind: .inGame, date: Date(timeIntervalSince1970: day * 86_400),
                        samples: samples, probeMsPerFrame: 0.3)
    }

    @Test func integratingTheSameSourceTwiceChangesNothing() {
        var h = ModImpactHistory()
        let s = source("seg#0", day: 1, ["Mod.A": sample("seg#0", day: 1)])
        let first = h.integrate(s)     // `mutating` : hors de la closure de #expect
        let once = h
        let second = h.integrate(s)
        #expect(first && !second)
        #expect(h == once)
        #expect(h.samples["mod.a"]?.count == 1)          // clé en minuscules
        #expect(h.probeMsPerFrame == 0.3)
    }

    @Test func negligibleSamplesAreDroppedButTheSourceIsMarked() {
        var h = ModImpactHistory()
        h.integrate(source("seg#0", day: 1, ["Mod.Tiny": sample("seg#0", day: 1, fps: 0.0001)
            .with(spike: 0.001, alloc: 0.0001)]))
        #expect(h.samples["mod.tiny"] == nil)
        #expect(h.integrated["seg#0"] != nil)
    }

    @Test func eachVersionAndKindKeepsItsThirtyNewest() {
        var h = ModImpactHistory()
        for day in 0..<35 {
            h.integrate(source("s\(day)", day: Double(day), ["Mod.A": sample("s\(day)", day: Double(day))]))
        }
        h.integrate(source("old", day: 0.5, ["Mod.A": sample("old", day: 0.5, version: "0.9")]))
        let list = h.samples["mod.a"] ?? []
        #expect(list.filter { $0.version == "1.0" }.count == 30)
        #expect(list.filter { $0.version == "1.0" }.map(\.sourceId).first == "s5")   // les 5 plus anciens sortis
        #expect(list.filter { $0.version == "0.9" }.count == 1)                      // autre version : son propre plafond
        #expect(h.integrated.count == 36)                                            // aucune source oubliée
    }

    @Test func roundTripsThroughDisk() throws {
        var h = ModImpactHistory()
        h.integrate(source("seg#0", day: 1, ["Mod.A": sample("seg#0", day: 1)]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("impact-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ModImpactHistory.load(from: url) == .absent)
        try h.save(to: url)
        #expect(ModImpactHistory.load(from: url) == .loaded(h))
    }

    @Test func anUnreadableHistoryIsReportedNotReplaced() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("impact-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"integrated\":".utf8).write(to: url)
        #expect(ModImpactHistory.load(from: url) == .unreadable)
    }
}

private extension ModImpactSample {
    func with(spike: Double, alloc: Double) -> ModImpactSample {
        ModImpactSample(sourceId: sourceId, kind: kind, date: date, version: version, msPerSecond: msPerSecond,
                        maxMs: maxMs, allocMBPerMinute: allocMBPerMinute, msPerFrame: msPerFrame,
                        frameWorkShare: frameWorkShare, patchesMeasured: patchesMeasured, ms: ms,
                        fpsShare: fpsShare, spikeShare: spike, allocShare: alloc, loadShare: loadShare)
    }
}
