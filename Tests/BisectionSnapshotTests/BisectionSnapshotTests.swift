import Testing
import Foundation
@testable import StarHubTHCore

@Suite(.serialized)
struct BisectionSnapshotTests {
    /// Les trois tests touchent au même fichier. Deux précautions :
    ///  - `.serialized` : ils ne se chevauchent pas (sinon le `clear()` de l'un
    ///    pouvait tomber entre le `save` et le `load` d'un autre → test flaky).
    ///  - dossier temporaire unique par test : on n'écrit jamais dans le vrai
    ///    Application Support, donc impossible d'écraser l'instantané réel
    ///    d'une recherche qu'un joueur aurait laissée en plan.
    private func useTempDir() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bisect-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        BisectionSnapshotStore.storageDirectory = dir
    }

    @Test func savedSnapshotComesBackIdentical() {
        useTempDir()
        let snap = BisectionSnapshot(enabledFolders: ["A", "B", "[CP] Pack"],
                                     startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        BisectionSnapshotStore.save(snap)
        #expect(BisectionSnapshotStore.load() == snap)
    }

    @Test func noSnapshotMeansNoInterruptedSession() {
        useTempDir()
        BisectionSnapshotStore.clear()
        #expect(BisectionSnapshotStore.load() == nil)
    }

    @Test func clearingRemovesTheSnapshot() {
        useTempDir()
        BisectionSnapshotStore.save(BisectionSnapshot(enabledFolders: ["A"], startedAt: Date()))
        BisectionSnapshotStore.clear()
        #expect(BisectionSnapshotStore.load() == nil)
    }
}
