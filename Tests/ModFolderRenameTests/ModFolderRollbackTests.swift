import Foundation
import Testing
@testable import StarHubTHCore

/// Le gestionnaire de fichiers qui scripte les échecs : les `allowedMoves`
/// premiers déplacements passent (réels, sur disque), les suivants lèvent.
///
/// C'est la seule façon de faire échouer le renommage sans toucher à la mise
/// de côté qui le précède : les deux gestes partagent le même dossier parent,
/// et un état disque figé avant l'appel ne peut pas distinguer le retour
/// arrière du geste qu'il défait — ce qui distingue les coups, c'est leur
/// **rang**. La sous-classe intercepte les appels directs de la fonction
/// testée (`fm.moveItem(atPath:toPath:)`, dispatch dynamique ordinaire) ;
/// le délégué `FileManagerDelegate`, lui, n'est pas consulté par le chemin
/// rapide `rename(2)` — constaté, pas supposé. La propriété `delegate` des
/// `FileManager` ne retient de toute façon pas son objet.
private final class ScriptedMoves: FileManager {
    /// Combien de déplacements laisser passer avant de refuser les suivants.
    let allowedMoves: Int
    /// Ce qui a été tenté, dans l'ordre — le test vérifie que le retour
    /// arrière a bien été tenté avant de déclarer son échec.
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

/// L'échec d'un renommage de dossier doit **dire** ce qui s'est passé —
/// tâche P5-T9 : l'échec de rollback remonte à l'appelant au lieu d'être
/// journalisé sur place.
@Suite struct ModFolderRollbackTests {

    @Test("un rollback rate dit où le dossier est resté")
    func aFailedRollbackNamesTheStrandedFolder() throws {
        // Arrange : un dossier temporaire — jamais le vrai Mods/.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModFolderRollback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = ScriptedMoves(allowedMoves: 1)

        // La source : le dossier du mod qu'on bascule.
        let src = root.appendingPathComponent("Source")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)

        // La destination : un résidu du **même** mod — le manifeste déclare
        // l'identifiant basculé, exactement ce qu'une bascule plantée laisse
        // derrière elle. Sans lui, la garde de collision refuserait avant
        // tout déplacement.
        let dst = root.appendingPathComponent("Cible")
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        try Data("{\"UniqueID\": \"a.b\"}".utf8)
            .write(to: dst.appendingPathComponent("manifest.json"))

        // Act + Assert.
        do {
            try ModFolderRename.moveReplacingStaleDestination(
                from: src.path, to: dst.path,
                destinationName: "Cible", uniqueId: "a.b", fm: fm)
            Issue.record("le renommage aurait dû échouer")
        } catch let failure as ModFolderRenameFailure {
            guard case .rollbackFailed(_, _, let strandedAt, let destination) = failure else {
                Issue.record("cas inattendu : \(failure)")
                return
            }
            // Les trois gestes ont bien eu lieu : mise de côté, déplacement
            // refusé, retour arrière refusé.
            #expect(fm.attempted.count == 3)
            // L'appelant apprend où le dossier est resté — et le chemin nommé
            // dit la vérité : le dossier écarté y est réellement, sous le nom
            // à point que `ModFolderCollision.asideName` donne. La
            // destination, elle, est vide : sans cette ligne CRITICAL, le
            // mod serait perdu des deux côtés sans un mot.
            #expect(strandedAt.hasPrefix(root.path + "/.Cible.stale_"))
            #expect(fm.fileExists(atPath: strandedAt))
            #expect(!fm.fileExists(atPath: dst.path))
            #expect(destination == dst.path)
            // Le mod basculé, lui, n'a pas bougé : c'est le résidu qui est
            // coincé dehors.
            #expect(fm.fileExists(atPath: src.path))
        } catch {
            Issue.record("type d'erreur inattendu : \(error)")
        }
    }

    /// Les trois appelants n'affichent que `error.localizedDescription` :
    /// l'emballage en `ModFolderRenameFailure.moveFailed` doit laisser
    /// passer le message de l'erreur d'origine, sinon toute bascule en
    /// échec se mettrait à dire « The operation couldn't be completed »
    /// sans dire pourquoi.
    @Test("un déplacement qui échoue seul garde le message de l'original")
    func aFailedMoveKeepsTheOriginalMessage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModFolderMove-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = ScriptedMoves(allowedMoves: 0)

        // Source seule, destination libre : pas de mise de côté, un seul
        // déplacement — refusé.
        let src = root.appendingPathComponent("Source")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        let dst = root.appendingPathComponent("Cible")

        do {
            try ModFolderRename.moveReplacingStaleDestination(
                from: src.path, to: dst.path,
                destinationName: "Cible", uniqueId: "a.b", fm: fm)
            Issue.record("le renommage aurait dû échouer")
        } catch let failure as ModFolderRenameFailure {
            guard case .moveFailed(let original) = failure else {
                Issue.record("cas inattendu : \(failure)")
                return
            }
            #expect(fm.attempted.count == 1)
            #expect(failure.localizedDescription == original.localizedDescription)
        } catch {
            Issue.record("type d'erreur inattendu : \(error)")
        }
    }
}
