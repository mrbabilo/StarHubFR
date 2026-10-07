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
        return ProbePerformanceStore(files: ProbeFiles(directory: probe),
                                     snapshotDirectory: root.appendingPathComponent("support"))
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
        await s.select(before: s.sides[0].id, after: s.sides[2].id).value
        #expect(s.report?.before.id == s.sides[0].id && s.report?.after.id == s.sides[2].id)
    }

    /// Une relecture garde l'écran : jamais de retour à `.loading` une fois prêt.
    @Test func reloadKeepsTheScreenOnceReady() async throws {
        let s = try store()
        await s.reload()
        await s.select(before: s.sides[0].id, after: s.sides[2].id).value
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
            return ProbeComparisonScope.make(before: s.sides[i], after: s.sides[j]).diff?.changes.contains {
                if case .configChanged = $0.kind { return true } else { return false }
            } == true
        }
        let selected = try #require(pair)
        await s.select(before: s.sides[selected.0].id, after: s.sides[selected.1].id).value
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

    /// Deux mesures guidées enchaînées closes : la paire qu'elles forment
    /// prend la sélection d'elle-même (retour d'utilisateur du 2026-10-04) —
    /// pas la mesure seule, et une relecture ultérieure ne la reprend plus.
    @Test func aFinishedGuidedPairTakesTheSelection() async throws {
        let s = try store()
        await s.reload()
        let target = try #require(s.sides.first { $0.minutes.count >= 4 })
        let beforeId = UUID(), afterId = UUID()
        func line(_ id: UUID, role: String, pairedWith: UUID?) -> String {
            let kept = (role == "before" ? Array(target.minutes.prefix(3)) : Array(target.minutes.suffix(3))).map(\.at)
            return """
            {"Version":1,"PlanId":"\(id.uuidString)","Name":"m","Role":"\(role)",\
            "PairedWith":\(pairedWith.map { "\"\($0.uuidString)\"" } ?? "null"),\
            "Session":"\(target.session)","Location":"Farm","Start":"\(kept.first!)","End":"\(kept.last!)",\
            "KeptAt":[\(kept.map { "\"\($0)\"" }.joined(separator: ","))],"Excluded":[],"Outcome":"stable",\
            "FrameIqrShare":0.02,"WorkIqrShare":0.02,"GameTimeFrom":600,"GameTimeTo":620,"Probe":"0.5.0"}
            """
        }
        let url = probe.appendingPathComponent("guided-measurements.jsonl")
        try (line(beforeId, role: "before", pairedWith: nil) + "\n").write(to: url, atomically: true, encoding: .utf8)
        await s.reload()
        #expect(s.afterId != "m:\(beforeId.uuidString)")   // seule, sans paire : rien ne bouge
        try (line(beforeId, role: "before", pairedWith: nil) + "\n"
             + line(afterId, role: "after", pairedWith: beforeId) + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
        await s.reload()
        #expect(s.beforeId == "m:\(beforeId.uuidString)")
        #expect(s.afterId == "m:\(afterId.uuidString)")
        await s.reload()
        #expect(s.afterId == "m:\(afterId.uuidString)")
    }
}

extension ProbePerformanceStoreTests {
    /// Deux sessions 0.6.0 : AutoForager présent (A), puis absent (B).
    private static let inventoryAB = """
    {"Session":"2026-09-30T20:00:00.0000000\\u002B02:00","At":"2026-09-30T20:00:20.0000000\\u002B02:00","Kind":"launch","Probe":"0.6.0","Smapi":"4.5.2","Game":"1.6.15","Mods":[{"Id":"Pathoschild.AutoForager","Version":"1.0.0","Config":null},{"Id":"mrbabilo.StarHubFR.Probe","Version":"0.6.0","Config":null}]}
    {"Session":"2026-09-30T21:00:00.0000000\\u002B02:00","At":"2026-09-30T21:00:20.0000000\\u002B02:00","Kind":"launch","Probe":"0.6.0","Smapi":"4.5.2","Game":"1.6.15","Mods":[{"Id":"mrbabilo.StarHubFR.Probe","Version":"0.6.0","Config":null}]}

    """

    @Test func loadsAreReadWithTheirComparison() async throws {
        let probe = root.appendingPathComponent("probe", isDirectory: true)
        try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
        try Self.inventoryAB.write(to: probe.appendingPathComponent("inventory.jsonl"), atomically: true, encoding: .utf8)
        try Fixture.data("loads.jsonl").write(to: probe.appendingPathComponent("loads.jsonl"))
        let s = ProbePerformanceStore(files: ProbeFiles(directory: probe))
        await s.reload()
        #expect(s.probeWritesLoads)
        #expect(s.lastSave?.record.session == "2026-09-30T21:00:00.0000000+02:00")
        let comparison = try #require(s.saveComparison)
        #expect(comparison.diff.changes.map(\.modId) == ["Pathoschild.AutoForager"])
        #expect(s.unreadableLines >= 1)   // la ligne tronquée de la fixture
    }

    @Test func olderProbeShowsNoLoadsAndKeepsTheTab() async throws {
        let s = try store()   // fixtures 0.4.x, sans loads.jsonl
        await s.reload()
        #expect(s.loads.isEmpty)
        #expect(!s.probeWritesLoads)
        #expect(s.status == .ready)
    }
}
