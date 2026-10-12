import Testing
import Foundation
@testable import StarHubTHCore

/// P1 §7 — `guided-pilot-state.json` : reprise après plantage, dossier
/// injecté sans valeur par défaut (patron `BenchmarkSnapshotStore`).
@Suite struct GuidedPilotStateStoreTests {
    private var directory: URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pilot-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func interruptedApplyingSurvivesRoundTrip() throws {
        let dir = directory
        var plan = GuidedPilotPlan.initial
        plan.begin(draft: .init(name: "A", role: .before, location: "Farm", pairedWith: nil),
                   gesture: .pauseMod(folderName: "Stardropium", modId: "Arshia1381.Stardropium"),
                   now: Date(timeIntervalSince1970: 0))
        plan.sideFinished(now: Date(timeIntervalSince1970: 60))   // applying
        #expect(GuidedPilotStateStore.save(plan, in: dir))
        let back = GuidedPilotStateStore.load(from: dir)
        #expect(back == plan)
        #expect(back?.phase == .applying)
        #expect(GuidedPilotStateStore.hasPending(in: dir))
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func clearRemovesTheFile() {
        let dir = directory
        defer { try? FileManager.default.removeItem(at: dir) }
        var plan = GuidedPilotPlan.initial
        plan.begin(draft: .init(name: "A", role: .before, location: "Farm", pairedWith: nil),
                   gesture: nil, now: Date(timeIntervalSince1970: 0))
        #expect(GuidedPilotStateStore.save(plan, in: dir))
        #expect(GuidedPilotStateStore.clear(in: dir))
        #expect(GuidedPilotStateStore.load(from: dir) == nil)
        #expect(GuidedPilotStateStore.clear(in: dir))   // idempotent
    }

    @Test func nilDirectoryAndAbsentFileAreNotPending() {
        #expect(GuidedPilotStateStore.load(from: nil) == nil)
        #expect(GuidedPilotStateStore.hasPending(in: nil) == false)
        #expect(GuidedPilotStateStore.hasPending(in: directory) == false)
    }
}
