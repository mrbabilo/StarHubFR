import Testing
import Foundation
@testable import StarHubTHCore

/// D1-T2 — le temps propre par mod, lu dans les `[RawLog]` de Profiler.
/// Lignes tirées du journal réel du 2026-09-29 (Profiler 2.0.0).
struct ProfilerCostsTests {
    /// SpaceCore à GameLaunched, 56,18 ms dont 1,14 ms d'enfants d'autres mods.
    private let spaceCore = #"[22:49:57 TRACE Profiler] [RawLog] {"OccuredAt":5000.7264,"Metadata":{"Duration":56.1826,"ModId":"spacechase0.SpaceCore","EventType":"GameLoop.GameLaunched","Details":"","InnerDetails":[{"OccuredAt":5013.7037,"Metadata":{"Duration":0.2361,"ModId":"aedenthorn.SoundTweaker","EventType":"Content.AssetRequested","Details":"","InnerDetails":[],"Type":"Duration"}},{"OccuredAt":5014.0783,"Metadata":{"Duration":0.1137,"ModId":"Cropgenics","EventType":"Content.AssetRequested","Details":"","InnerDetails":[],"Type":"Duration"}},{"OccuredAt":5014.3821,"Metadata":{"Duration":0.3871,"ModId":"DIGUS.MailFrameworkMod","EventType":"Content.AssetRequested","Details":"","InnerDetails":[],"Type":"Duration"}},{"OccuredAt":5026.4381,"Metadata":{"Duration":0.2217,"ModId":"DIGUS.MailFrameworkMod","EventType":"Content.AssetReady","Details":"","InnerDetails":[],"Type":"Duration"}},{"OccuredAt":5041.6996,"Metadata":{"Duration":0.1842,"ModId":"DIGUS.MailFrameworkMod","EventType":"Content.AssetRequested","Details":"","InnerDetails":[],"Type":"Duration"}}],"Type":"Duration"}}"#
    /// La ligne `Init` : type `Base`, sans durée — ne compte pas.
    private let initLine = #"[22:49:52 TRACE Profiler] [RawLog] {"OccuredAt":1.4763,"Metadata":{"ModId":"SinZ.Profiler","EventType":"SinZ.Profiler/Init","Details":"2026-09-29T22:49:52.0354190+02:00","InnerDetails":[],"Type":"Base"}}"#

    private func line(_ at: Double, _ mod: String, _ ms: Double, _ event: String = "GameLoop.UpdateTicked") -> String {
        #"[22:52:00 TRACE Profiler] [RawLog] {"OccuredAt":\#(at),"Metadata":{"Duration":\#(ms),"ModId":"\#(mod)","EventType":"\#(event)","Details":"","InnerDetails":[],"Type":"Duration"}}"#
    }

    @Test func childrenAreSubtractedAndAttributedToTheirOwnMod() throws {
        let costs = ProfilerCosts(log: [initLine, spaceCore].joined(separator: "\n"))
        #expect(costs.rawLogLines == 2)
        #expect(costs.unreadableLines == 0)
        let spaceCoreSelf = try #require(costs.byMod(.launch).first { $0.modId == "spacechase0.SpaceCore" })
        #expect(abs(spaceCoreSelf.selfMs - (56.1826 - 1.1428)) < 0.0001)
        let mail = try #require(costs.byMod(.launch).first { $0.modId == "DIGUS.MailFrameworkMod" })
        #expect(abs(mail.selfMs - 0.793) < 0.0001)
        // La somme des temps propres rend la durée de la racine : rien compté deux fois.
        #expect(abs(costs.total(.launch) - 56.1826) < 0.0001)
        #expect(!costs.byMod(.launch).contains { $0.modId == "SinZ.Profiler" })
    }

    @Test func markersSplitLaunchLoadAndPlay() {
        let log = [
            line(1000, "A", 10),
            "[22:51:23 INFO  Profiler] [91,565.59][Fast] LoadStageChanged None -> SaveParsed",
            line(100_000, "A", 20),
            "[22:52:46 INFO  Profiler] [174,706.72][Slow] Day Started",
            line(174_706.72, "B", 5),   // borne incluse : encore le chargement
            line(180_000, "A", 7),
        ].joined(separator: "\r\n")     // CRLF : même découpage
        let costs = ProfilerCosts(log: log)
        #expect(costs.hasLoadMarkers)
        #expect(costs.total(.launch) == 10)
        #expect(costs.total(.load) == 25)
        #expect(costs.total(.play) == 7)
        #expect(costs.byMod(.load).map(\.modId) == ["A", "B"])
    }

    @Test func withoutMarkersEverythingIsLaunch() {
        let costs = ProfilerCosts(log: [line(1, "A", 6), line(500_000, "A", 4)].joined(separator: "\n"))
        #expect(!costs.hasLoadMarkers)
        #expect(costs.total(.launch) == 10)
        #expect(costs.costs.first?.calls == 2)
        #expect(costs.costs.first?.maxSelfMs == 6)
    }

    /// Un format qui change se voit : compté, pas avalé ; une ligne d'un
    /// autre mod qui imite le préfixe n'entre pas.
    @Test func unreadableAndForeignLinesAreKeptApart() {
        let log = [
            "[22:52:00 TRACE Profiler] [RawLog] {pas du json",
            "[22:52:00 TRACE OtherMod] [RawLog] {\"OccuredAt\":1}",
            line(1, "A", 6),
        ].joined(separator: "\n")
        let costs = ProfilerCosts(log: log)
        #expect(costs.rawLogLines == 2)
        #expect(costs.unreadableLines == 1)
        #expect(costs.total(.launch) == 6)
    }

    @Test func markerNumbersFollowTheLogCulture() {
        #expect(ProfilerCosts.marker("[4,606.15][Fast] Game Launched")?.at == 4606.15)
        #expect(ProfilerCosts.marker("[4 606,15][Slow] Game Launched")?.at == 4606.15)
        #expect(ProfilerCosts.marker("[12.5][Fast] Save Loaded")?.name == "Save Loaded")
        #expect(ProfilerCosts.marker("[12.5] Save Loaded") == nil)
    }
}
