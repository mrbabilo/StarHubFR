import Testing
import Foundation
@testable import StarHubTHCore

struct BisectionSnapshotTests {
    /// Un dossier temporaire **par test**, passé en paramètre au store.
    ///
    /// Deux propriétés que l'ancienne redirection par `static var` n'avait pas :
    ///  - rien ne peut atterrir dans le vrai Application Support, puisque le
    ///    store n'a plus de valeur par défaut à oublier et que cette suite ne
    ///    nomme jamais `AppSupport` ;
    ///  - plus besoin de `.serialized` — le `clear()` d'un test ne peut plus
    ///    tomber entre le `save` et le `load` d'un autre, chacun ayant son
    ///    propre dossier.
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bisect-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func savedSnapshotComesBackIdentical() {
        let dir = tempDir()
        let snap = BisectionSnapshot(enabledFolders: ["A", "B", "[CP] Pack"],
                                     startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        BisectionSnapshotStore.save(snap, in: dir)
        #expect(BisectionSnapshotStore.load(from: dir) == snap)
    }

    /// **Le test qui épingle la redirection.** Les autres n'observent que
    /// l'aller-retour du store : ils resteraient verts si les quatre points
    /// d'entrée ignoraient le dossier reçu et se donnaient rendez-vous ailleurs
    /// — y compris dans le vrai Application Support. Celui-ci regarde le
    /// disque à l'endroit exact qui a été demandé.
    @Test func theSnapshotIsWrittenInTheDirectoryItWasGiven() {
        let dir = tempDir()
        BisectionSnapshotStore.save(BisectionSnapshot(enabledFolders: ["A"], startedAt: Date()),
                                    in: dir)
        let file = dir.appendingPathComponent("bisection_snapshot.json")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func noSnapshotMeansNoInterruptedSession() {
        let dir = tempDir()
        BisectionSnapshotStore.clear(in: dir)
        #expect(BisectionSnapshotStore.load(from: dir) == nil)
    }

    @Test func clearingRemovesTheSnapshot() {
        let dir = tempDir()
        BisectionSnapshotStore.save(BisectionSnapshot(enabledFolders: ["A"], startedAt: Date()), in: dir)
        BisectionSnapshotStore.clear(in: dir)
        #expect(BisectionSnapshotStore.load(from: dir) == nil)
    }

    /// Sans dossier de support, l'app ne peut rien persister : le store se tait
    /// au lieu d'échouer, et une lecture rend « rien ». C'est le comportement
    /// qu'avait `storageDirectory == nil` — il survit au passage en paramètre.
    @Test func noDirectoryMeansNoStorageAndNoCrash() {
        BisectionSnapshotStore.save(BisectionSnapshot(enabledFolders: ["A"], startedAt: Date()),
                                    in: nil)
        #expect(BisectionSnapshotStore.load(from: nil) == nil)
        BisectionSnapshotStore.clear(in: nil)
        #expect(BisectionSnapshotStore.finish(.complete, in: nil) == true)
    }

    /// Le cas dangereux : une remise en état qui n'aboutit qu'à moitié.
    /// Effacer l'instantané laisserait des mods en pause **et** supprimerait la
    /// seule trace de l'état de départ. Il doit survivre, pour que l'utilisateur
    /// puisse réessayer — au prochain démarrage s'il le faut.
    @Test func anIncompleteRestoreKeepsTheSnapshot() {
        let dir = tempDir()
        let snap = BisectionSnapshot(enabledFolders: ["A", "B", "[CP] Pack"],
                                     startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        BisectionSnapshotStore.save(snap, in: dir)

        #expect(BisectionSnapshotStore.finish(.partial(failedCount: 1), in: dir) == false)
        #expect(BisectionSnapshotStore.load(from: dir) == snap)

        // L'obstacle levé (dossier refermé, jumeau retiré), la remise en état
        // aboutit : c'est seulement là qu'on a le droit d'oublier.
        #expect(BisectionSnapshotStore.finish(.complete, in: dir) == true)
        #expect(BisectionSnapshotStore.load(from: dir) == nil)
    }

    @Test func theOutcomeIsReadFromTheNumberOfFailedMoves() {
        #expect(BisectionRestoreOutcome(moveFailures: 0) == .complete)
        #expect(BisectionRestoreOutcome(moveFailures: 1) == .partial(failedCount: 1))
        #expect(BisectionRestoreOutcome(moveFailures: 7) == .partial(failedCount: 7))
    }
}
