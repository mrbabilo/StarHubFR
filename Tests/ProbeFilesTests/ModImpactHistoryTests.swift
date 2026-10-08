import Foundation
import Testing
@testable import StarHubTHCore

struct ModImpactHistoryTests {
    private func sample(_ source: String, day: Double, version: String? = "1.0", fps: Double = 0.2,
                        kind: ModImpactSample.Kind = .inGame) -> ModImpactSample {
        ModImpactSample(sourceId: source, kind: kind, date: Date(timeIntervalSince1970: day * 86_400),
                        version: version, msPerSecond: 1, maxMs: 1, allocMBPerMinute: 1, msPerFrame: 0.1,
                        frameWorkShare: 0.01, patchesMeasured: true, ms: nil,
                        fpsShare: fps, spikeShare: 0.5, allocShare: 0.1, loadShare: nil, textureMB: nil)
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

    /// Revue finale C1 : jeter les échantillons sous le plancher biaisait la
    /// médiane vers le haut (un mod lourd 1 session sur 3 prenait la note de
    /// cette seule session). Ils sont gardés.
    @Test func negligibleSamplesAreKeptSoTheMedianStaysHonest() throws {
        var h = ModImpactHistory()
        h.integrate(source("s0", day: 1, ["Mod.A": sample("s0", day: 1, fps: 0.0001).with(spike: 0.001, alloc: 0.0001)]))
        h.integrate(source("s1", day: 2, ["Mod.A": sample("s1", day: 2, fps: 0.0001).with(spike: 0.001, alloc: 0.0001)]))
        h.integrate(source("s2", day: 3, ["Mod.A": sample("s2", day: 3, fps: 0.25)]))
        #expect(h.samples["mod.a"]?.count == 3)
        let stats = try #require(ModImpact.versionStats(h.samples["mod.a"] ?? []).first)
        #expect(stats.shares[.fps] == 0.0001)
        #expect(stats.sourceCount == 3)
    }

    /// Revue finale I6 : un champ absent (historique d'une version antérieure,
    /// ou champ futur ajouté) ne rend jamais l'historique « illisible ».
    @Test func missingOrUnknownFieldsStillDecode() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("impact-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"integrated\":{},\"futureField\":1}".utf8).write(to: url)
        #expect(ModImpactHistory.load(from: url) == .loaded(ModImpactHistory()))
        try Data("{}".utf8).write(to: url)
        #expect(ModImpactHistory.load(from: url) == .loaded(ModImpactHistory()))
    }

    /// Revue finale C2 : les démarrages vus sont retenus, sans doublon.
    @Test func bootsAreRememberedOnce() {
        var h = ModImpactHistory()
        let boot = Date(timeIntervalSince1970: 1_000)
        h.noteBoot(boot)
        h.noteBoot(boot)
        h.noteBoot(Date(timeIntervalSince1970: 2_000))
        #expect(h.boots == [boot, Date(timeIntervalSince1970: 2_000)])
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
                        fpsShare: fpsShare, spikeShare: spike, allocShare: alloc, loadShare: loadShare, textureMB: nil)
    }
}
