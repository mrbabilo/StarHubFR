import Foundation

/// Un pas de boucle en masse rendu à l'appelant. Les échecs portent leurs
/// messages PRÉ-CALCULÉS (Strings Sendable) — le VM ne reçoit jamais
/// d'`Error` existentiel (dette L5 refusée ici).
enum BulkMoveEvent: Sendable {
    /// Progression : `done` dossiers traités sur `total`. Le throttling est
    /// décidé par `progressStep` côté exécutant.
    case progress(done: Int, total: Int)
    /// Un dossier vient de bouger vers l'état actif : l'appelant pose son
    /// horodatage à la réception — l'ordre des événements est l'ordre du plan.
    case activated(folderName: String)
    /// La boucle est allée au bout. Toujours le dernier événement.
    case finished(BulkMoveOutcome)
}

/// Le bilan de fin de boucle : ce qui a été tenté, ce qui a bougé, ce qui a
/// échoué — dans l'ordre du plan.
struct BulkMoveOutcome: Sendable {
    let attempted: Int
    let movedCount: Int
    /// Un par échec, dans l'ordre du plan. `criticalLog` est la ligne
    /// `CRITICAL:` pré-calculée d'un rollback raté — `nil` pour un échec
    /// simple. `message` est `error.localizedDescription` pré-calculé.
    let failures: [BulkMoveFailure]
}

/// Un renommage en masse resté sur le carreau. `folderName` est le nom
/// **logique** — la clé des magasins du VM ; `modName` le nom affiché.
struct BulkMoveFailure: Sendable {
    let folderName: String
    let modName: String
    let direction: ProfileApplyPlan.Direction
    let criticalLog: String?
    let message: String
}

/// L'exécutant des boucles de renommage en masse (P5-L3) : prend les moves
/// d'un plan, les exécute sur une file de fond, rend chaque étape par un
/// canal explicite — la progression, les activations, le résultat final.
///
/// **Pourquoi ça existe.** `toggleAllMods` et `applyProfileToFilesystem`
/// étaient structurellement jumelles : instantané pris sur main, passage en
/// file globale, renommages `Mods/X` ↔ `Mods/.X`, hops main pour la barre,
/// bilan à la fin — avec leur `MoveFailure` dupliqué et zéro test possible
/// (une closure interne à un `@MainActor` n'est pas dans `Tests/`). Le
/// calcul de plan était déjà en Core (`ProfileApplyPlan`, `TogglePlan`) ;
/// il manquait l'**exécutant**.
///
/// Le canal est explicite par construction : l'exécutant ne connaît ni le
/// ViewModel, ni la localisation, ni les magasins — il rend des événements,
/// l'appelant écrit son état, journalise et dit son bilan. Les messages
/// d'erreur sont pré-calculés **ici** en `String` : seul un `String`
/// traverse (patron de l'appelant bascule en masse depuis T9), et le VM ne
/// reçoit jamais d'`Error` existentiel à travers le fil.
enum ModFolderBulkMove {

    /// Exécute les renommages sur une file de fond et rend les événements.
    /// `skipMissingSource` reproduit le comportement de la bascule en masse
    /// (source déjà disparue = traité, pas un échec) ; `false` = le
    /// comportement du profil (source disparue = échec nommé).
    /// `progressStep` : un événement de progression tous les N dossiers
    /// traités, plus le dernier — 1 = chaque dossier.
    /// `makeFileManager` est une factory : le `FileManager` est créé DANS la
    /// queue d'exécution (il ne traverse pas — non-Sendable), et les tests
    /// y injectent leur `ScriptedMoves`.
    static func execute(_ moves: [ProfileApplyPlan.Move],
                        in modsPath: String,
                        skipMissingSource: Bool,
                        progressStep: Int,
                        makeFileManager: @escaping @Sendable () -> FileManager = { .default }
    ) -> AsyncStream<BulkMoveEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Créé DANS la queue : FileManager ne traverse pas (T9/T10).
                let fm = makeFileManager()
                var failures: [BulkMoveFailure] = []
                var attempted = 0
                var movedCount = 0
                let total = moves.count
                let step = max(1, progressStep)

                func yieldProgress(done: Int) {
                    guard done == total || done % step == 0, total > 0 else { return }
                    continuation.yield(.progress(done: done, total: total))
                }

                for move in moves {
                    attempted += 1
                    let src = (modsPath as NSString).appendingPathComponent(move.source)
                    let dst = (modsPath as NSString).appendingPathComponent(move.destination)

                    if skipMissingSource, !fm.fileExists(atPath: src) {
                        yieldProgress(done: attempted)
                        continue
                    }

                    do {
                        try ModFolderRename.moveReplacingStaleDestination(
                            from: src, to: dst,
                            destinationName: move.destination,
                            uniqueId: move.uniqueId, fm: fm)
                        movedCount += 1
                        if move.direction == .enable {
                            continuation.yield(.activated(folderName: move.folderName))
                        }
                    } catch let failure as ModFolderRenameFailure {
                        failures.append(BulkMoveFailure(
                            folderName: move.folderName, modName: move.modName,
                            direction: move.direction,
                            criticalLog: failure.rollbackCriticalLog,
                            message: failure.errorDescription ?? String(describing: failure)))
                    } catch {
                        failures.append(BulkMoveFailure(
                            folderName: move.folderName, modName: move.modName,
                            direction: move.direction,
                            criticalLog: nil,
                            message: error.localizedDescription))
                    }
                    yieldProgress(done: attempted)
                }

                continuation.yield(.finished(BulkMoveOutcome(
                    attempted: attempted, movedCount: movedCount, failures: failures)))
                continuation.finish()
            }
        }
    }
}
