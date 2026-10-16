import Testing
import Foundation
@testable import StarHubTHCore

/// R5 (audit UX 2026-10-16, I-T26) : un historique écrit par une version plus
/// récente — un geste inconnu d'ici — ne doit pas emporter les autres
/// instantanés. Le décodage synthétisé échouait sur le fichier entier.
struct ActivationHistoryDecodingTests {

    private func snapshotJSON(gesture: String, id: UUID = UUID()) -> String {
        """
        {"id":"\(id.uuidString)","takenAt":0,"gesture":"\(gesture)","enabledFolders":["A"],
         "pausedFolders":["B"],"pinned":false}
        """
    }

    @Test func anUnknownGestureSkipsOnlyItsSnapshot() throws {
        let kept = UUID()
        let json = "{\"snapshots\":[\(snapshotJSON(gesture: "bisection")),\(snapshotJSON(gesture: "profile", id: kept))]}"
        let history = try JSONDecoder().decode(ActivationHistory.self, from: Data(json.utf8))
        #expect(history.snapshots.map(\.id) == [kept])
    }

    @Test func aReadableHistoryRoundTrips() throws {
        var history = ActivationHistory()
        history.record(ActivationSnapshot(takenAt: Date(timeIntervalSince1970: 10), gesture: .bulkEnable,
                                          detail: "12", enabledFolders: ["A"], pausedFolders: [],
                                          activeProfileId: nil),
                       now: Date(timeIntervalSince1970: 20))
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode(ActivationHistory.self, from: data) == history)
    }

    @Test func aFileWithoutSnapshotsIsAnEmptyHistory() throws {
        #expect(try JSONDecoder().decode(ActivationHistory.self, from: Data("{}".utf8)).snapshots.isEmpty)
    }
}
