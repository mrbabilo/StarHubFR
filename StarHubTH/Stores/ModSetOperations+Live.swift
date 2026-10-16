import Foundation

/// R5 — l'état des trois opérations qui tiennent le parc, lu sur leurs
/// runners. La règle vit dans `ModSetOperations` (Core) ; ceci ne fait que
/// la nourrir. Hors du fichier du ViewModel (règle F1-T2).
extension StarHubTHViewModel {
    var modSetOperations: ModSetOperations {
        let pilot = self.pilot
        return ModSetOperations(
            bisectionRunning: bisection.state != nil,
            bisectionInterrupted: bisection.interruptedSnapshot != nil,
            benchmarkRunning: benchmark.isActive,
            benchmarkInterrupted: benchmark.interrupted != nil,
            pilotRunning: pilot.isActive,
            // Une paire finie (`.reporting`) reste côté « après » par choix :
            // ce n'est pas une interruption.
            pilotInterrupted: pilot.canRollback && pilot.state.phase != .reporting)
    }
}
