import Foundation
import Testing
@testable import StarHubTHCore

private actor PerformanceLoadGate {
    private var continuation: CheckedContinuation<ProbePerformanceSnapshot, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var didStart = false
    func load() async -> ProbePerformanceSnapshot {
        await withCheckedContinuation {
            continuation = $0
            didStart = true
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ snapshot: ProbePerformanceSnapshot) {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }
}

@MainActor struct ProbePerformanceOrderingTests {
    @Test func olderLoadCannotOverwriteNewerSnapshot() async throws {
        let gate = PerformanceLoadGate()
        let a = PerformanceFixture.side("A", minutes: [try PerformanceFixture.minute(index: 0)])
        let b = PerformanceFixture.side("B", minutes: [try PerformanceFixture.minute(index: 10)])
        let store = ProbePerformanceStore(loader: { path in
            if path == "slow" { return await gate.load() }
            return ProbePerformanceSnapshot(sides: [b])
        })
        let old = Task { await store.reload(gameDir: "slow") }
        await gate.waitUntilStarted()
        await store.reload(gameDir: "fast")
        await gate.finish(ProbePerformanceSnapshot(sides: [a]))
        await old.value
        #expect(store.sides.map(\.id) == ["B"])
        #expect(store.singleSummary?.side.session == "B")
    }

    @Test func sameSelectionHasVisibleReasonAndLatestSelectionWins() async throws {
        let sides = try (0..<3).map { index in
            PerformanceFixture.side("\(index)", minutes: try (0..<5).map { try PerformanceFixture.minute(index: index * 10 + $0) })
        }
        let store = ProbePerformanceStore(loader: { _ in ProbePerformanceSnapshot(sides: sides) })
        await store.reload()
        let old = store.select(before: "0", after: "1")
        let new = store.select(before: "2", after: "2")
        #expect(store.report == nil)
        #expect(store.configDiffs.isEmpty)
        await new.value
        await old.value
        #expect(store.report?.before.id == "2" && store.report?.after.id == "2")
        #expect(store.report?.scope.issues.contains(.sameSelection) == true)
    }
}
