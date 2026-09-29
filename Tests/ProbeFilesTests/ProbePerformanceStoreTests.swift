import Testing
import Foundation
@testable import StarHubTHCore

@Suite @MainActor struct ProbePerformanceStoreTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("perf-store-\(UUID().uuidString)", isDirectory: true)

    private func store(withFixtures: Bool = true) throws -> ProbePerformanceStore {
        let probe = root.appendingPathComponent("probe", isDirectory: true)
        if withFixtures {
            try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
            for name in ["timings.jsonl", "mod-costs.jsonl", "inventory.jsonl"] {
                try Fixture.data(name).write(to: probe.appendingPathComponent(name))
            }
        }
        return ProbePerformanceStore(files: ProbeFiles(directory: probe))
    }

    @Test func loadsSidesAndTheDefaultPair() async throws {
        let s = try store()
        await s.reload()
        #expect(s.status == .ready)
        #expect(s.sides.count == 6)
        #expect(s.afterId?.hasSuffix("#1") == true)
        #expect(s.report?.after.id == s.afterId)
        // 2 lignes coupées (trames, coûts) + 1 (inventaire).
        #expect(s.unreadableLines == 3)
    }

    /// Review Focus 3 — pas de sonde : un statut, aucune erreur, aucun fichier.
    @Test func noProbeDirectoryIsAStatus() async throws {
        let s = try store(withFixtures: false)
        await s.reload()
        #expect(s.status == .noProbe)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("probe/guided-plan.json").path))
    }

    @Test func selectingAnotherPairRebuildsTheReport() async throws {
        let s = try store()
        await s.reload()
        s.select(before: s.sides[0].id, after: s.sides[2].id)
        #expect(s.report?.before.id == s.sides[0].id && s.report?.after.id == s.sides[2].id)
    }

    /// Une relecture garde l'écran : jamais de retour à `.loading` une fois prêt.
    @Test func reloadKeepsTheScreenOnceReady() async throws {
        let s = try store()
        await s.reload()
        s.select(before: s.sides[0].id, after: s.sides[2].id)
        let pair = (s.beforeId, s.afterId)
        let reloading = Task { await s.reload() }
        await Task.yield()  // la relecture tourne jusqu'à sa lecture en fond
        #expect(s.status == .ready)
        await reloading.value
        #expect(s.status == .ready)
        #expect(s.beforeId == pair.0 && s.afterId == pair.1)
        await s.configDiffsLoaded()
    }

    /// Le réglage GMCM changé en cours de session : ses diffs clé par clé
    /// arrivent dans le store après la sélection de la paire qui le traverse.
    @Test func selectingAPairLoadsItsConfigDiffs() async throws {
        let s = try store()
        let configs = root.appendingPathComponent("probe/configs", isDirectory: true)
        try FileManager.default.createDirectory(at: configs, withIntermediateDirectories: true)
        for (sha, json) in [("3fa643ce93584e8a987ee1f06e0cd407eecaf3eee51d82027a61748ecb412be4", "{\"a\":1}"),
                            ("bbe0048abc4eef1bbe3c560ad66f995e22bbbfbc3676896a1bef8449eae072ea", "{\"a\":2}")] {
            try json.write(to: configs.appendingPathComponent("\(sha).json"), atomically: true, encoding: .utf8)
        }
        await s.reload()
        let pair = s.sides.indices.flatMap { i in s.sides.indices.map { (i, $0) } }.first { i, j in
            guard i < j else { return false }
            s.select(before: s.sides[i].id, after: s.sides[j].id)
            return s.report?.diff?.changes.contains {
                if case .configChanged = $0.kind { return true } else { return false }
            } == true
        }
        #expect(pair != nil)
        await s.configDiffsLoaded()
        #expect(s.configDiffs["spacechase0.GenericModConfigMenu"]?.map(\.path) == ["a"])
    }

    private var probe: URL { root.appendingPathComponent("probe", isDirectory: true) }

    @Test func prepareWritesThePlanAndAbandonRemovesIt() async throws {
        let s = try store()
        let plan = try s.prepare(GuidedPlanDraft(name: "m", role: .before, location: "Farm", pairedWith: nil))
        #expect(GuidedPlan.load(from: probe.appendingPathComponent("guided-plan.json")) == plan)
        #expect(s.protocolState == .planPending(plan))
        try s.abandonPlan()
        #expect(GuidedPlan.load(from: probe.appendingPathComponent("guided-plan.json")) == nil)
        #expect(s.protocolState == .idle)
    }

    /// Une mesure close relue : l'app efface son plan (seule écrivaine) et la
    /// mesure devient un côté, restreint à ses minutes gardées.
    @Test func finishedMeasurementClearsItsPlanAndBecomesASide() async throws {
        let s = try store()
        await s.reload()
        let target = try #require(s.sides.first { $0.minutes.count >= 4 })
        let plan = try s.prepare(GuidedPlanDraft(name: "m", role: .before, location: "Farm", pairedWith: nil))
        let kept = target.minutes.prefix(3).map(\.at)
        let line = """
        {"Version":1,"PlanId":"\(plan.id.uuidString)","Name":"m","Role":"before","PairedWith":null,\
        "Session":"\(target.session)","Location":"Farm","Start":"\(kept.first!)","End":"\(kept.last!)",\
        "KeptAt":[\(kept.map { "\"\($0)\"" }.joined(separator: ","))],"Excluded":[],"Outcome":"stable",\
        "FrameIqrShare":0.02,"WorkIqrShare":0.02,"GameTimeFrom":600,"GameTimeTo":620,"Probe":"0.5.0"}
        """
        try (line + "\n").write(to: probe.appendingPathComponent("guided-measurements.jsonl"),
                                atomically: true, encoding: .utf8)
        await s.reload()
        #expect(s.plan == nil)
        #expect(GuidedPlan.load(from: probe.appendingPathComponent("guided-plan.json")) == nil)
        let side = try #require(s.sides.first { $0.measurement?.id == plan.id })
        #expect(side.minutes.count == 3)
        if case .beforeDone(let m) = s.protocolState { #expect(m.id == plan.id) } else { Issue.record("état") }
    }
}
