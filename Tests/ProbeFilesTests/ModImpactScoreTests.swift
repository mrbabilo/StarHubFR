import Foundation
import Testing
@testable import StarHubTHCore

struct ModImpactScoreTests {
    private func inGame(_ source: String, day: Double, version: String?, fps: Double, spike: Double,
                        alloc: Double, msPerFrame: Double = 1) -> ModImpactSample {
        ModImpactSample(sourceId: source, kind: .inGame, date: Date(timeIntervalSince1970: day * 86_400),
                        version: version, msPerSecond: msPerFrame * 30, maxMs: 10, allocMBPerMinute: 5,
                        msPerFrame: msPerFrame, frameWorkShare: 0.02, patchesMeasured: day < 2, ms: nil,
                        fpsShare: fps, spikeShare: spike, allocShare: alloc, loadShare: nil, textureMB: nil)
    }
    private func launch(_ source: String, day: Double, version: String?, share: Double, ms: Double) -> ModImpactSample {
        ModImpactSample(sourceId: source, kind: .launch, date: Date(timeIntervalSince1970: day * 86_400),
                        version: version, msPerSecond: nil, maxMs: nil, allocMBPerMinute: nil, msPerFrame: nil,
                        frameWorkShare: nil, patchesMeasured: nil, ms: ms,
                        fpsShare: nil, spikeShare: nil, allocShare: nil, loadShare: share, textureMB: nil)
    }
    private func mod(_ id: String, version: String, enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: id, name: id, folderName: id, version: version, author: "", description: "",
                nexusUrl: "", nexusModId: "", isEnabled: enabled, dependencies: [])
    }
    private func source(_ id: String, day: Double, _ samples: [String: ModImpactSample]) -> ModImpactSource {
        ModImpactSource(id: id, kind: .inGame, date: Date(timeIntervalSince1970: day * 86_400),
                        samples: samples, probeMsPerFrame: nil)
    }

    @Test func scoreIsWeightedRootsWithoutRenormalising() {
        // Un seul axe mesuré à 4 % : 15 × √0,04 = 3, pas 100 × √0,04 = 20.
        #expect(abs(ModImpact.score([.launch: 0.04]) - 3) < 1e-9)
        let all: [ModImpactAxis: Double] = [.fps: 0.25, .spikes: 1, .launch: 0.04, .save: 0.01, .alloc: 0.09]
        // 35×0,5 + 20×1 + 15×0,2 + 15×0,1 + 15×0,3 = 46,5
        #expect(abs(ModImpact.score(all) - 46.5) < 1e-9)
        #expect(ModImpact.impactClass(score: 15) == .high)
        #expect(ModImpact.impactClass(score: 14.99) == .medium)
        #expect(ModImpact.impactClass(score: 5) == .medium)
        #expect(ModImpact.impactClass(score: 4.99) == .low)
    }

    @Test func medianPerAxisPerVersionAndUnmeasuredAxesStayAbsent() throws {
        let samples = [inGame("a", day: 1, version: "1.0", fps: 0.1, spike: 0.2, alloc: 0.05),
                       inGame("b", day: 2, version: "1.0", fps: 0.3, spike: 0.4, alloc: 0.05),
                       inGame("c", day: 3, version: "1.0", fps: 0.2, spike: 0.9, alloc: 0.05),
                       launch("l", day: 3, version: "1.0", share: 0.04, ms: 2_000)]
        let stats = try #require(ModImpact.versionStats(samples).first)
        #expect(stats.shares[.fps] == 0.2 && stats.shares[.spikes] == 0.4 && stats.shares[.launch] == 0.04)
        #expect(stats.shares[.save] == nil)                       // non mesuré ≠ 0
        #expect(stats.ranges[.spikes] == 0.2...0.9)
        #expect(stats.sourceCount == 4 && stats.inGameSources == 3 && stats.patchedSources == 1)
        #expect(stats.launchMs == 2_000 && stats.saveMs == nil)
        #expect(ModImpact.median([1, 2, 3, 4]) == 2.5)
    }

    @Test func aNewVersionShowsTheLastKnownNoteMarked() throws {
        var h = ModImpactHistory()
        h.integrate(source("a", day: 1, ["Mod.A": inGame("a", day: 1, version: "1.2", fps: 0.1, spike: 0.1, alloc: 0.1)]))
        let entry = try #require(ModImpact.entries(history: h, mods: [mod("Mod.A", version: "1.3")]).first)
        #expect(entry.current == nil)
        #expect(entry.shown?.version == "1.2")
        #expect(entry.evolution == nil)
    }

    @Test func evolutionNeedsThreeSourcesOnBothVersions() throws {
        var h = ModImpactHistory()
        for (i, v) in ["1.0", "1.0", "1.0", "1.1", "1.1"].enumerated() {
            let fps = v == "1.0" ? 0.25 : 0.04
            h.integrate(source("s\(i)", day: Double(i),
                               ["Mod.A": inGame("s\(i)", day: Double(i), version: v, fps: fps, spike: 0, alloc: 0)]))
        }
        #expect(ModImpact.entries(history: h, mods: [mod("Mod.A", version: "1.1")]).first?.evolution == nil)   // 2 sources en 1.1
        h.integrate(source("s5", day: 5, ["Mod.A": inGame("s5", day: 5, version: "1.1", fps: 0.04, spike: 0, alloc: 0)]))
        let entry = try #require(ModImpact.entries(history: h, mods: [mod("Mod.A", version: "1.1")]).first)
        // 35 × √0,04 − 35 × √0,25 = 7 − 17,5 = −10,5 : un gain.
        #expect(abs(try #require(entry.evolution) + 10.5) < 1e-9)
        #expect(entry.versions.map(\.version) == ["1.1", "1.0"])
    }

    @Test func entriesMatchUniqueIdsIgnoringCaseAndSkipTheProbe() throws {
        var h = ModImpactHistory()
        h.integrate(source("a", day: 1, ["pathoschild.contentpatcher":
            inGame("a", day: 1, version: "2.0", fps: 0.3, spike: 0.3, alloc: 0.3)]))
        let entries = ModImpact.entries(history: h, mods: [mod("Pathoschild.ContentPatcher", version: "2.0"),
                                                           mod(BenchmarkSides.probeId, version: "0.9.0")])
        #expect(entries.map(\.modId) == ["Pathoschild.ContentPatcher"])
        #expect(entries.first?.current != nil)
    }

    @Test func rankingKeepsEnabledMeasuredNonNegligibleByScore() {
        var h = ModImpactHistory()
        let rows: [(String, Double)] = [("Mod.Low", 0.01), ("Mod.High", 0.5), ("Mod.Paused", 0.9)]
        for (i, (id, fps)) in rows.enumerated() {
            h.integrate(source("s\(i)", day: 1, [id: inGame("s\(i)", day: 1, version: "1", fps: fps, spike: 0, alloc: 0)]))
        }
        let entries = ModImpact.entries(history: h, mods: [mod("Mod.Low", version: "1"), mod("Mod.High", version: "1"),
                                                           mod("Mod.Paused", version: "1", enabled: false),
                                                           mod("Mod.Never", version: "1")])
        #expect(ModImpact.ranking(entries).map(\.modId) == ["Mod.High", "Mod.Low"])
        #expect(entries.first { $0.modId == "Mod.Never" }?.shown == nil)
    }

    /// Un mod mesuré seulement sous le plancher est « négligeable », pas
    /// « jamais mesuré » (parc réel du 2026-10-01 : 170 mods dits non mesurés).
    @Test func aModSeenOnlyUnderTheFloorIsNegligibleNotUnmeasured() throws {
        var h = ModImpactHistory()
        h.integrate(source("a", day: 1, ["Mod.Tiny": inGame("a", day: 1, version: "1", fps: 0.0001, spike: 0.001, alloc: 0.0001)]))
        let entries = ModImpact.entries(history: h, mods: [mod("Mod.Tiny", version: "1"), mod("Mod.Never", version: "1")])
        let tiny = try #require(entries.first { $0.modId == "Mod.Tiny" })
        #expect(tiny.shown != nil && tiny.isNegligible)
        #expect(entries.first { $0.modId == "Mod.Never" }?.isNegligible == false)
        #expect(ModImpact.ranking(entries).isEmpty)
    }

    /// « version inconnue » (segment sans inventaire) n'est pas une version à
    /// comparer : un mod mesuré en 1.0 et sans inventaire n'a qu'une version.
    @Test func unknownVersionIsNotAComparableVersion() throws {
        var h = ModImpactHistory()
        h.integrate(source("a", day: 1, ["Mod.A": inGame("a", day: 1, version: nil, fps: 0.2, spike: 0.2, alloc: 0.2)]))
        h.integrate(source("b", day: 2, ["Mod.A": inGame("b", day: 2, version: "1.0", fps: 0.2, spike: 0.2, alloc: 0.2)]))
        let entry = try #require(ModImpact.entries(history: h, mods: [mod("Mod.A", version: "1.0")]).first)
        #expect(entry.versions.count == 2)
        #expect(entry.comparableVersionCount == 1)
    }

    /// Revue finale I3 : le manifeste dit « 7.4 », l'inventaire de la sonde
    /// (normalisé par SMAPI) « 7.4.0 » — même version (12 mods du parc).
    @Test func installedVersionMatchesSemantically() throws {
        var h = ModImpactHistory()
        h.integrate(source("a", day: 1, ["Mod.A": inGame("a", day: 1, version: "7.4.0", fps: 0.2, spike: 0.2, alloc: 0.2)]))
        let entry = try #require(ModImpact.entries(history: h, mods: [mod("Mod.A", version: "7.4")]).first)
        #expect(entry.current?.version == "7.4.0")
        #expect(ModImpact.sameVersion("1.0-beta", "1.0.0-BETA"))
        #expect(!ModImpact.sameVersion("1.0", "1.0.1"))
        #expect(!ModImpact.sameVersion("1.0", "1.0-beta"))
        #expect(!ModImpact.sameVersion(nil, "1.0"))
    }

    /// Revue finale I4 : « version inconnue » n'est ni la note affichée faute
    /// de mieux, ni la version précédente d'une évolution.
    @Test func unknownVersionNeverStandsInForAKnownOne() throws {
        var h = ModImpactHistory()
        var day = 0.0
        func add(_ v: String?, fps: Double) {
            day += 1
            h.integrate(source("s\(day)", day: day, ["Mod.A": inGame("s\(day)", day: day, version: v, fps: fps, spike: 0, alloc: 0)]))
        }
        for _ in 0..<3 { add("1.0", fps: 0.25) }
        for _ in 0..<3 { add(nil, fps: 0.01) }
        let before = try #require(ModImpact.entries(history: h, mods: [mod("Mod.A", version: "1.1")]).first)
        #expect(before.current == nil)
        #expect(before.shown?.version == "1.0")              // pas la version inconnue, plus récente
        for _ in 0..<3 { add("1.1", fps: 0.04) }
        let after = try #require(ModImpact.entries(history: h, mods: [mod("Mod.A", version: "1.1")]).first)
        #expect(abs(try #require(after.evolution) + 10.5) < 1e-9)   // contre 1.0, pas contre l'inconnue
        #expect(after.previousVersion?.version == "1.0")
    }

    /// Revue mineure : n par axe — lancements et sauvegardes comptés à part.
    @Test func versionStatsCountSourcesPerKind() throws {
        let samples = [inGame("a", day: 1, version: "1", fps: 0.1, spike: 0.1, alloc: 0.1),
                       launch("l1", day: 1, version: "1", share: 0.01, ms: 10),
                       launch("l2", day: 2, version: "1", share: 0.01, ms: 10)]
        let stats = try #require(ModImpact.versionStats(samples).first)
        #expect(stats.inGameSources == 1 && stats.launchSources == 2 && stats.saveSources == 0)
    }

    /// La partie en cours est la plus récente **en date** : au passage à
    /// l'heure d'hiver, « …02:10+01:00 » suit « …02:30+02:00 » alors que la
    /// chaîne la classe avant.
    @Test func theOpenSessionIsTheLatestByDateNotByString() {
        let before = "2026-10-25T02:30:00.0000000+02:00"   // 00:30 UTC
        let after = "2026-10-25T02:10:00.0000000+01:00"    // 01:10 UTC
        #expect(ModImpactSources.latestSession([before, after]) == after)
    }

    @Test func gameProcessNameMatchesWithoutCase() {
        #expect(GameProcess.isGame(localizedName: "Stardew Valley"))
        #expect(GameProcess.isGame(localizedName: "stardew valley"))
        #expect(!GameProcess.isGame(localizedName: "Stardew Valley Launcher"))
        #expect(!GameProcess.isGame(localizedName: nil))
    }
}
