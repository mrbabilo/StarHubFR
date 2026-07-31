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

    /// Le cas dangereux : une remise en état qui n'aboutit qu'à moitié.
    /// Effacer l'instantané laisserait des mods en pause **et** supprimerait la
    /// seule trace de l'état de départ. Il doit survivre, pour que l'utilisateur
    /// puisse réessayer — au prochain démarrage s'il le faut.
    @Test func anIncompleteRestoreKeepsTheSnapshot() {
        useTempDir()
        let snap = BisectionSnapshot(enabledFolders: ["A", "B", "[CP] Pack"],
                                     startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        BisectionSnapshotStore.save(snap)

        #expect(BisectionSnapshotStore.finish(.partial(failedCount: 1)) == false)
        #expect(BisectionSnapshotStore.load() == snap)

        // L'obstacle levé (dossier refermé, jumeau retiré), la remise en état
        // aboutit : c'est seulement là qu'on a le droit d'oublier.
        #expect(BisectionSnapshotStore.finish(.complete) == true)
        #expect(BisectionSnapshotStore.load() == nil)
    }

    @Test func theOutcomeIsReadFromTheNumberOfFailedMoves() {
        #expect(BisectionRestoreOutcome(moveFailures: 0) == .complete)
        #expect(BisectionRestoreOutcome(moveFailures: 1) == .partial(failedCount: 1))
        #expect(BisectionRestoreOutcome(moveFailures: 7) == .partial(failedCount: 7))
    }
}
