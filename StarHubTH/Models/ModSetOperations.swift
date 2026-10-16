import Foundation

/// R5 (audit UX 2026-10-16) — les opérations qui déplacent des dossiers de
/// mods sous un instantané qui leur est propre : la recherche du mod
/// responsable (bissection), le benchmark A/B et la mesure pilotée.
///
/// Tant que l'une est en cours, ou interrompue sans avoir été remise, le parc
/// n'est pas dans l'état que l'utilisateur croit : « Revenir à un état
/// d'avant » (R5) déplacerait des dossiers **sous** cet instantané. Et
/// l'Accueil doit dire laquelle attend sa remise.
struct ModSetOperations: Equatable {
    /// Ordre fixe, celui de l'encart de l'Accueil.
    enum Operation: CaseIterable, Equatable {
        case bisection, benchmark, pilot
    }

    let running: Set<Operation>
    let interrupted: Set<Operation>

    /// Celles qui attendent leur remise, dans l'ordre d'affichage. Une
    /// opération qui a repris n'y figure plus.
    var awaitingRestore: [Operation] {
        Operation.allCases.filter { interrupted.contains($0) && !running.contains($0) }
    }

    /// Celle qui interdit un retour R5 : en cours d'abord, sinon interrompue.
    var blocking: Operation? {
        Operation.allCases.first(where: running.contains) ?? awaitingRestore.first
    }

    /// - Parameters:
    ///   - bisectionInterrupted: un instantané de recherche reste à remettre.
    ///   - pilotInterrupted: la mesure pilotée a été interrompue **après**
    ///     avoir déplacé des dossiers (`GuidedPilotRunner.canRollback`) ;
    ///     sans geste joué, il n'y a rien à remettre.
    init(bisectionRunning: Bool, bisectionInterrupted: Bool,
         benchmarkRunning: Bool, benchmarkInterrupted: Bool,
         pilotRunning: Bool, pilotInterrupted: Bool) {
        var running: Set<Operation> = []
        var interrupted: Set<Operation> = []
        if bisectionRunning { running.insert(.bisection) }
        if bisectionInterrupted { interrupted.insert(.bisection) }
        if benchmarkRunning { running.insert(.benchmark) }
        if benchmarkInterrupted { interrupted.insert(.benchmark) }
        if pilotRunning { running.insert(.pilot) }
        if pilotInterrupted { interrupted.insert(.pilot) }
        self.running = running
        self.interrupted = interrupted
    }
}
