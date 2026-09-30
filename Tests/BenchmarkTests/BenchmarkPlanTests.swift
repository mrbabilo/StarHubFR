import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct BenchmarkPlanTests {
    private func ids() -> () -> String { var n = 0; return { n += 1; return "r\(n)" } }

    @Test func twoWarmupsThenAlternatedSides() {
        let runs = BenchmarkSequence.runs(perSide: 3, sameState: false, makeId: ids())
        #expect(runs.map(\.side) == [.warmupA, .warmupB, .a, .b, .a, .b, .a, .b])
        #expect(runs.map(\.id) == (1...8).map { "r\($0)" })
    }

    @Test func sameStateHasASingleWarmup() {
        let runs = BenchmarkSequence.runs(perSide: 2, sameState: true, makeId: ids())
        #expect(runs.map(\.side) == [.warmupA, .a, .b, .a, .b])
    }

    @Test func fewerThanTwoPerSideIsRaisedToTwo() {
        let runs = BenchmarkSequence.runs(perSide: 1, sameState: false, makeId: ids())
        #expect(runs.filter { $0.side == .a }.count == 2)
        #expect(runs.filter { $0.side == .b }.count == 2)
    }

    @Test func sidesKnowWhetherTheyCountAndWhichStateTheyUse() {
        #expect(!BenchmarkSide.warmupA.counts && !BenchmarkSide.warmupB.counts)
        #expect(BenchmarkSide.a.counts && BenchmarkSide.b.counts)
        #expect(BenchmarkSide.warmupA.isA && BenchmarkSide.a.isA)
        #expect(!BenchmarkSide.warmupB.isA && !BenchmarkSide.b.isA)
    }

    @Test func planFileRoundTripsWithPascalCaseKeysAndNoFractions() throws {
        // Relecture finale : la fenêtre de détournement d'un lancement manuel
        // reste courte — le plan est écrit juste avant le lancement du jeu,
        // que la sonde lit à sa propre Entry (~1 min).
        #expect(BenchmarkPlanFile.lifetime == 300)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("benchmark-plan.json")
        let plan = BenchmarkPlanFile(runId: "r1", saveName: "TestOK_444827372_bench",
                                     expiresAt: Date(timeIntervalSince1970: 1_790_000_000.7))
        try plan.write(to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"RunId\"") && text.contains("\"SaveName\"") && text.contains("\"ExpiresAt\""))
        #expect(text.contains("\"Version\" : 1"))
        #expect(!text.contains(".7"))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(BenchmarkPlanFile.self, from: Data(contentsOf: url)) == plan)
        try BenchmarkPlanFile.remove(at: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try BenchmarkPlanFile.remove(at: url)   // absent : pas d'erreur
    }
}
