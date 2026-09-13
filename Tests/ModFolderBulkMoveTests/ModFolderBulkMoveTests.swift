import Foundation
import Testing
@testable import StarHubTHCore

/// Le gestionnaire de fichiers qui scripte les échecs : les `allowedMoves`
/// premiers déplacements passent (réels, sur disque), les suivants lèvent.
///
/// Copié de `ModFolderRollbackTests.swift`, où il est `private` : chaque
/// suite duplique son harnais, les deux n'en partagent qu'une idée, pas un
/// fichier. Voir là-bas pour le raisonnement — c'est le rang du coup, pas
/// l'état du disque, qui distingue les gestes.
private final class ScriptedMoves: FileManager, @unchecked Sendable {
    /// Combien de déplacements laisser passer avant de refuser les suivants.
    let allowedMoves: Int
    /// Ce qui a été tenté, dans l'ordre.
    private(set) var attempted: [(from: String, to: String)] = []

    init(allowedMoves: Int) {
        self.allowedMoves = allowedMoves
        super.init()
    }

    override func moveItem(atPath srcPath: String, toPath dstPath: String) throws {
        attempted.append((srcPath, dstPath))
        guard attempted.count > allowedMoves else {
            return try super.moveItem(atPath: srcPath, toPath: dstPath)
        }
        throw CocoaError(.fileWriteUnknown)
    }
}

/// L'exécutant des boucles de renommage en masse (P5-L3 T1) : chaque règle du
/// canal d'événements épinglée sur un disque réel — dossiers temporaires
/// UUID, jamais le vrai `Mods/`. L'exécution des boucles n'avait aucun test
/// quand elle vivait dans le ViewModel ; c'est ce qu'ici elle redevient.
@Suite struct ModFolderBulkMoveTests {

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModFolderBulkMove-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root,
                                                withIntermediateDirectories: true)
        defer { } // le vrai defer est posé par l'appelant
        return root
    }

    /// Un move prêt à réussir : dossier source présent, destination libre.
    /// Le sens suit `ProfileApplyPlan.Direction` : enable = `.X` → `X`.
    private func move(folderName: String, enabled: Bool,
                      in root: URL) throws -> ProfileApplyPlan.Move {
        let srcName = enabled ? "." + folderName : folderName
        let dstName = enabled ? folderName : "." + folderName
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(srcName), withIntermediateDirectories: true)
        return ProfileApplyPlan.Move(folderName: folderName, modName: folderName,
                                     uniqueId: "a." + folderName,
                                     source: srcName, destination: dstName,
                                     direction: enabled ? .enable : .disable)
    }

    /// Drain le stream et rend les événements dans l'ordre.
    private func collect(_ stream: AsyncStream<BulkMoveEvent>) async -> [BulkMoveEvent] {
        var events: [BulkMoveEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    private func progressValues(of events: [BulkMoveEvent]) -> [(Int, Int)] {
        events.compactMap {
            if case .progress(let done, let total) = $0 { return (done, total) }
            return nil
        }
    }

    private func activatedNames(of events: [BulkMoveEvent]) -> [String] {
        events.compactMap {
            if case .activated(let folderName) = $0 { return folderName }
            return nil
        }
    }

    private func outcome(of events: [BulkMoveEvent]) -> BulkMoveOutcome? {
        for event in events {
            if case .finished(let outcome) = event { return outcome }
        }
        return nil
    }

    @Test("un move enable réussi dit activated, progress, finished — dans cet ordre")
    func aSingleMoveYieldsProgressActivationAndOutcome() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let m = try move(folderName: "X", enabled: true, in: root)

        let events = await collect(ModFolderBulkMove.execute(
            [m], in: root.path, skipMissingSource: false, progressStep: 1))

        // Le disque a suivi : la source est partie, la destination est là.
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".X").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("X").path))

        guard events.count == 3 else {
            Issue.record("3 événements attendus, obtenus : \(events.count)")
            return
        }
        // L'activation d'abord : l'horodatage se pose sur un dossier qui a
        // bougé, avant le pas de progression du même dossier — règle du
        // canal, patron des deux boucles du ViewModel.
        guard case .activated(let folderName) = events[0] else {
            Issue.record("premier événement inattendu : \(events[0])")
            return
        }
        #expect(folderName == "X")
        guard case .progress(let done, let total) = events[1] else {
            Issue.record("second événement inattendu : \(events[1])")
            return
        }
        #expect(done == 1)
        #expect(total == 1)
        guard case .finished(let outcome) = events[2] else {
            Issue.record("troisième événement inattendu : \(events[2])")
            return
        }
        #expect(outcome.attempted == 1)
        #expect(outcome.movedCount == 1)
        #expect(outcome.failures.isEmpty)
    }

    @Test("un move disable réussi ne dit pas activated")
    func aDisabledMoveYieldsNoActivationEvent() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let m = try move(folderName: "X", enabled: false, in: root)

        let events = await collect(ModFolderBulkMove.execute(
            [m], in: root.path, skipMissingSource: false, progressStep: 1))

        // Le disque a suivi dans l'autre sens.
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("X").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".X").path))
        // L'horodatage d'activation ne se pose qu'à l'activation : pas
        // d'événement `activated` sur une mise en pause.
        #expect(activatedNames(of: events).isEmpty)
        let o = outcome(of: events)
        #expect(o?.movedCount == 1)
        #expect(o?.failures.isEmpty == true)
    }

    @Test("source absente et skip demandé : traité, pas un échec")
    func missingSourceIsSkippedWhenSkipIsAsked() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let m = try move(folderName: "X", enabled: true, in: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent(".X"))

        let events = await collect(ModFolderBulkMove.execute(
            [m], in: root.path, skipMissingSource: true, progressStep: 1))

        let o = outcome(of: events)
        #expect(o?.attempted == 1)
        #expect(o?.movedCount == 0)
        #expect(o?.failures.isEmpty == true)
        // La barre ne se fige pas : le pas est publié quand même.
        let progresses = progressValues(of: events)
        #expect(progresses.map(\.0) == [1])
        #expect(progresses.allSatisfy { $0.1 == 1 })
    }

    @Test("source absente et skip non demandé : un échec nommé")
    func missingSourceIsAFailureWhenSkipIsNotAsked() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // Jamais créée : la source n'a jamais existé.
        let m = ProfileApplyPlan.Move(folderName: "X", modName: "X", uniqueId: "a.X",
                                      source: "X", destination: ".X", direction: .enable)

        let events = await collect(ModFolderBulkMove.execute(
            [m], in: root.path, skipMissingSource: false, progressStep: 1))

        let o = outcome(of: events)
        #expect(o?.attempted == 1)
        #expect(o?.movedCount == 0)
        guard let failure = o?.failures.first else {
            Issue.record("échec attendu, aucun rapporté")
            return
        }
        #expect(failure.folderName == "X")
        #expect(!failure.message.isEmpty)
    }

    @Test("250 moves, pas de 50 : la progression throttle et finit par le dernier")
    func progressThrottlesByStepAndAlwaysEndsWithTheLastOne() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var moves: [ProfileApplyPlan.Move] = []
        moves.reserveCapacity(250)
        for i in 0..<250 {
            moves.append(try move(folderName: "m\(i)", enabled: true, in: root))
        }

        let events = await collect(ModFolderBulkMove.execute(
            moves, in: root.path, skipMissingSource: false, progressStep: 50))

        let progresses = progressValues(of: events)
        #expect(progresses.map(\.0) == [50, 100, 150, 200, 250])
        #expect(progresses.allSatisfy { $0.1 == 250 })
        let o = outcome(of: events)
        #expect(o?.movedCount == 250)
        #expect(o?.failures.isEmpty == true)
    }

    @Test("une collision étrangère refuse et nomme le mod — sans toucher l'étranger")
    func aForeignCollisionFailsAndNamesTheMod() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let m = try move(folderName: "X", enabled: true, in: root)
        // La destination de l'enable est `X` — occupée par un dossier portant
        // un manifeste d'un AUTRE identifiant : la garde de collision refuse.
        let dst = root.appendingPathComponent("X")
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        try Data("{\"UniqueID\": \"b.c\"}".utf8)
            .write(to: dst.appendingPathComponent("manifest.json"))

        let events = await collect(ModFolderBulkMove.execute(
            [m], in: root.path, skipMissingSource: false, progressStep: 1))

        let o = outcome(of: events)
        guard let failure = o?.failures.first else {
            Issue.record("échec attendu, aucun rapporté")
            return
        }
        #expect(failure.folderName == "X")
        #expect(!failure.message.isEmpty)
        #expect(failure.criticalLog == nil)
        #expect(o?.movedCount == 0)
        // Le dossier étranger est toujours là — ni déplacé, ni supprimé.
        #expect(FileManager.default.fileExists(atPath: dst.path))
        #expect(FileManager.default.fileExists(
            atPath: dst.appendingPathComponent("manifest.json").path))
        // Et la source à basculer n'a pas bougé non plus.
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".X").path))
    }

    @Test("un rollback raté pré-calcule la ligne CRITICAL et le chemin du stranded")
    func aFailedRollbackPreCalculatesTheCriticalLog() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let m = try move(folderName: "X", enabled: true, in: root)
        // Un résidu DU MÊME mod à destination (même identifiant que le move) :
        // la mise de côté passe (coup 1), le déplacement est refusé (coup 2),
        // la remise en place aussi (coup 3) — d'où `ScriptedMoves(1)`.
        let dst = root.appendingPathComponent("X")
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        try Data("{\"UniqueID\": \"a.X\"}".utf8)
            .write(to: dst.appendingPathComponent("manifest.json"))

        let fm = ScriptedMoves(allowedMoves: 1)
        let events = await collect(ModFolderBulkMove.execute(
            [m], in: root.path, skipMissingSource: false, progressStep: 1,
            makeFileManager: { fm }))

        let o = outcome(of: events)
        #expect(o?.movedCount == 0)
        guard let failure = o?.failures.first else {
            Issue.record("échec attendu, aucun rapporté")
            return
        }
        guard let criticalLog = failure.criticalLog else {
            Issue.record("criticalLog attendu, obtenu nil (message : \(failure.message))")
            return
        }
        #expect(criticalLog.contains("CRITICAL: toggle rollback failed"))
        // Les trois gestes ont bien eu lieu : mise de côté, déplacement
        // refusé, remise en place refusée.
        #expect(fm.attempted.count == 3)
        // Le chemin strandedAt que porte la ligne dit la vérité : le dossier
        // écarté y est réellement, sous le nom à point que
        // `ModFolderCollision.asideName` donne — le pont T9 transporté
        // jusqu'au bulk.
        guard let start = criticalLog.range(of: "mod still in "),
              let end = criticalLog.range(of: " (could not move back") else {
            Issue.record("format inattendu : \(criticalLog)")
            return
        }
        let strandedAt = String(criticalLog[start.upperBound..<end.lowerBound])
        #expect(strandedAt.hasPrefix(root.path + "/.X.stale_"))
        #expect(FileManager.default.fileExists(atPath: strandedAt))
    }

    @Test("le bilan ferme toujours la marche — dernier événement, rien après")
    func theOutcomeIsAlwaysTheLastEvent() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try move(folderName: "A", enabled: true, in: root)
        let second = try move(folderName: "B", enabled: true, in: root)
        let third = try move(folderName: "C", enabled: true, in: root)
        // La troisième destination appartient à un autre mod : un échec.
        let thirdDst = root.appendingPathComponent("C")
        try FileManager.default.createDirectory(at: thirdDst, withIntermediateDirectories: true)
        try Data("{\"UniqueID\": \"b.c\"}".utf8)
            .write(to: thirdDst.appendingPathComponent("manifest.json"))

        let events = await collect(ModFolderBulkMove.execute(
            [first, second, third], in: root.path, skipMissingSource: false,
            progressStep: 1))

        guard let last = events.last, case .finished(let outcome) = last else {
            Issue.record("dernier événement inattendu : \(String(describing: events.last))")
            return
        }
        #expect(outcome.attempted == 3)
        #expect(outcome.movedCount == 2)
        #expect(outcome.failures.count == 1)
        // 3 progressions + 2 activations + 1 bilan, pas un événement de plus :
        // rien ne suit jamais le bilan.
        #expect(events.count == 6)
        #expect(activatedNames(of: events) == ["A", "B"])
    }
}
