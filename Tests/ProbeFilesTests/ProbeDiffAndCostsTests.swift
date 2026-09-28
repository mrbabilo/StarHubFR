import Testing
import Foundation
@testable import StarHubTHCore

struct ProbeDiffAndCostsTests {
    private func entry(_ id: String, version: String, sha: String? = nil) -> ProbeInventoryEntry {
        ProbeInventoryEntry(modId: id, version: version, configSha: sha)
    }
    private func launch(_ mods: [ProbeInventoryEntry], probe: String = "0.4.13",
                        session: String = "s") -> ProbeInventoryLaunch {
        ProbeInventoryLaunch(session: session, at: Date(timeIntervalSince1970: 0),
                             probe: probe, mods: mods)
    }

    @Test func detectsAddedRemovedVersionAndConfig() {
        let a = launch([entry("Mod.A", version: "1.0", sha: "aa"), entry("Mod.B", version: "2.0"),
                        entry("Mod.C", version: "1.1", sha: "cc"),
                        entry("mrbabilo.StarHubFR.Probe", version: "0.4.12")])
        let b = launch([entry("Mod.A", version: "1.1", sha: "aa"),   // version changée
                        entry("Mod.C", version: "1.1", sha: "dd"),   // réglage changé
                        entry("Mod.D", version: "1.0"),              // ajouté
                        entry("mrbabilo.StarHubFR.Probe", version: "0.4.13")])
        let diff = ProbeInventoryDiffRule.between(a, b)
        #expect(diff.probeChanged)
        // Trié par modId ; la sonde mise à part.
        #expect(diff.changes == [
            ProbeModChange(modId: "Mod.A", kind: .versionChanged(from: "1.0", to: "1.1")),
            ProbeModChange(modId: "Mod.B", kind: .removed),
            ProbeModChange(modId: "Mod.C", kind: .configChanged(oldSha: "cc", newSha: "dd")),
            ProbeModChange(modId: "Mod.D", kind: .added),
        ])
    }

    /// SMAPI compare les identifiants sans la casse : un mod dont l'id change
    /// de casse entre deux versions n'est ni ajouté ni retiré.
    @Test func modIdsMatchWithoutCase() {
        let a = launch([entry("Some.Mod", version: "1.0")])
        let b = launch([entry("some.mod", version: "1.1")])
        #expect(ProbeInventoryDiffRule.between(a, b).changes
                == [ProbeModChange(modId: "some.mod", kind: .versionChanged(from: "1.0", to: "1.1"))])
        #expect(!ProbeInventoryDiffRule.between(a, a).probeChanged)
    }

    /// Contenus absents : « réglage modifié » seul, jamais de crash.
    @Test func configDiffNeedsBothContents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("probe-diff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "{\"a\":1}".write(to: directory.appendingPathComponent("aa.json"), atomically: true, encoding: .utf8)
        try "{\"a\":2,\"b\":3}".write(to: directory.appendingPathComponent("dd.json"), atomically: true, encoding: .utf8)
        let present = ProbeInventoryDiffRule.configDiff(modId: "Mod.C", oldSha: "aa", newSha: "dd",
                                                        configsDirectory: directory)
        #expect(present?.map(\.path) == ["a", "b"])
        #expect(ProbeInventoryDiffRule.configDiff(modId: "Mod.C", oldSha: "aa", newSha: "ff",
                                                  configsDirectory: directory) == nil)
        #expect(ProbeInventoryDiffRule.configDiff(modId: "Mod.C", oldSha: nil, newSha: "dd",
                                                  configsDirectory: directory) == nil)
        // L'empreinte vient d'un fichier : jamais un chemin.
        #expect(ProbeInventoryDiffRule.configDiff(modId: "Mod.C", oldSha: "../aa", newSha: "dd",
                                                  configsDirectory: directory.appendingPathComponent("x")) == nil)
    }

    private func cost(minute: ProbeComparableMinute, mods: [(String, Double)]) -> ProbeModCostMinute {
        let modsJSON = mods.map { "{\"Mod\":\"\($0.0)\",\"SelfMs\":\($0.1 * 60),\"MsPerSecond\":\($0.1),\"MaxMs\":\($0.1 * 2),\"AllocKB\":0,\"Calls\":1,\"Events\":[]}" }
        let json = """
        {"Session":"\(minute.minute.session)","At":"\(minute.minute.at)","WallSeconds":60,
         "Frames":45,"Location":"Farm","PatchesMeasured":false,"Mods":[\(modsJSON.joined(separator: ","))]}
        """
        return try! ProbeJSON.decoder().decode(ProbeModCostMinute.self, from: Data(json.utf8))
    }

    private func guardMinute(at: String) -> ProbeComparableMinute {
        let json = """
        {"Session":"s","At":"2026-09-28\(at)","WallSeconds":60,"Fps":30,
         "FrameInterval":{"Count":45,"Avg":30,"P50":30,"P99":50,"Max":60},
         "InactiveTicks":0,"HeapMB":4000,"LoadedMods":289,"Location":"Farm","MenuTicks":0,
         "Tick":{"Count":60,"Avg":20,"P50":20,"P99":40,"Max":50},"GameTime":650}
        """
        return ProbeComparableMinute(
            minute: try! ProbeJSON.decoder().decode(ProbeMinute.self, from: Data(json.utf8)),
            patchesMeasured: false)
    }

    @Test func costsAverageOverComparableMinutes() throws {
        let minutes = [guardMinute(at: "T10:00:00.0000000+02:00"),
                       guardMinute(at: "T10:01:00.0000000+02:00"),
                       guardMinute(at: "T10:05:00.0000000+02:00")]   // sans ligne appariée
        let costs = [cost(minute: minutes[0], mods: [("Mod.A", 1.0), ("Mod.B", 2.0)]),
                     cost(minute: minutes[1], mods: [("Mod.A", 3.0)])]
        let perMod = ProbeCosts.perMod(minutes, costs: costs)
        // somme(SelfMs) / somme(WallSeconds) : Mod.A = 240/120 = 2.0 ; la
        // minute sans ligne de coûts n'ajoute pas ses secondes.
        #expect(abs(try #require(perMod["Mod.A"]) - 2.0) < 0.001)
        // Mod.B absent de la seconde ligne : 0 cette minute — 120/120 = 1.0.
        #expect(abs(try #require(perMod["Mod.B"]) - 1.0) < 0.001)
    }

    @Test func costDeltasCarryWholeCostWhenAbsentAndSortByImpact() {
        let deltas = ProbeCosts.delta(["Mod.A": 1.0, "Mod.B": 0.5, "Mod.C": 2.0],
                                      ["Mod.A": 1.5, "Mod.C": 2.0, "Mod.D": 3.0])
        #expect(deltas.map(\.modId) == ["Mod.D", "Mod.A", "Mod.B", "Mod.C"])
        #expect(deltas.map(\.delta) == [3.0, 0.5, -0.5, 0])
        #expect(deltas.map(\.presence) == [.added, .both, .removed, .both])
    }
}
