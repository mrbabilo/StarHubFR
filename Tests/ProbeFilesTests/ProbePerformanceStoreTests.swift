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
                                     measurementsDirectory: root.appendingPathComponent("data"))
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
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("data").path))
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

    /// Démarrer exige le jeu lancé ; terminer, non (Review Focus 4).
    @Test func measurementNeedsTheGameToStartButNotToStop() async throws {
        let s = try store()
        await s.reload()
        #expect(!s.startMeasurement(name: "essai", gameRunning: false))
        #expect(s.openMeasurement == nil)
        #expect(s.startMeasurement(name: "essai", gameRunning: true))
        #expect(s.openMeasurement?.name == "essai")
        s.stopMeasurement()
        #expect(s.openMeasurement == nil)
        let reread = ProbeMeasurementsFile.load(directory: root.appendingPathComponent("data"))
        guard case .measurements(let saved) = reread else { Issue.record("illisible"); return }
        #expect(saved.count == 1 && saved[0].end != nil)
    }
}
