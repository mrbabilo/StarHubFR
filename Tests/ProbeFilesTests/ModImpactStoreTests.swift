import Foundation
import Testing
@testable import StarHubTHCore

@Suite @MainActor struct ModImpactStoreTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("impact-store-\(UUID().uuidString)", isDirectory: true)
    private var historyURL: URL { root.appendingPathComponent("ModImpactHistory.json") }

    /// `withLoads: false` pour les tests qui lisent le fichier d'historique :
    /// un lancement de fixture est « froid » ou non selon l'heure de démarrage
    /// du Mac qui exécute (`ProbeColdDisk`), ce qui rendrait l'écriture aléatoire.
    private func store(withLoads: Bool = true) throws -> ModImpactStore {
        let probe = root.appendingPathComponent("probe", isDirectory: true)
        try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
        var files = [("impact-timings.jsonl", "timings.jsonl"), ("impact-mod-costs.jsonl", "mod-costs.jsonl"),
                     ("impact-inventory.jsonl", "inventory.jsonl")]
        if withLoads { files.append(("loads-load.jsonl", "loads.jsonl")) }
        for (from, to) in files {
            try Fixture.data(from).write(to: probe.appendingPathComponent(to))
        }
        return ModImpactStore(files: ProbeFiles(directory: probe), historyURL: historyURL)
    }
    private let mods = [ModItem(uniqueId: "Pathoschild.ContentPatcher", name: "Content Patcher",
                                folderName: "ContentPatcher", version: "2.0", author: "", description: "",
                                nexusUrl: "", nexusModId: "", isEnabled: true, dependencies: [])]

    @Test func reloadingTwiceDoesNotGrowTheHistory() async throws {
        let s = try store(withLoads: false)
        await s.reload(mods: mods, gameRunning: false, gameDir: nil)
        #expect(s.status == .ready)
        let first = try Data(contentsOf: historyURL)
        await s.reload(mods: mods, gameRunning: false, gameDir: nil)
        #expect(try Data(contentsOf: historyURL) == first)
        #expect(s.entry(for: mods[0])?.shown != nil)
        #expect(s.lastInGame != nil)
    }

    @Test func theOpenSessionIsNotIntegratedWhileTheGameRuns() async throws {
        let s = try store(withLoads: false)
        await s.reload(mods: mods, gameRunning: true, gameDir: nil)
        // La seule session est la dernière : rien d'intégré, donc rien d'écrit.
        #expect(ModImpactHistory.load(from: historyURL) == .absent)
        await s.reload(mods: mods, gameRunning: false, gameDir: nil)
        guard case .loaded(let after) = ModImpactHistory.load(from: historyURL) else {
            Issue.record("historique absent"); return
        }
        #expect(after.integrated.keys.contains { $0.contains("#") })
    }

    @Test func anUnreadableHistoryIsNeverOverwritten() async throws {
        let s = try store()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let garbage = Data("{\"integrated\":".utf8)
        try garbage.write(to: historyURL)
        await s.reload(mods: mods, gameRunning: false, gameDir: nil)
        #expect(s.status == .unreadableHistory)
        #expect(try Data(contentsOf: historyURL) == garbage)
    }
}
