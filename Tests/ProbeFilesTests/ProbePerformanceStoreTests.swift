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
