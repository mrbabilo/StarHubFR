import Foundation
import Testing
@testable import StarHubTHCore

/// R5 — ce qui tient le parc sous son propre instantané.
@Suite struct ModSetOperationsTests {

    private func ops(bisectionRunning: Bool = false, bisectionInterrupted: Bool = false,
                     benchmarkRunning: Bool = false, benchmarkInterrupted: Bool = false,
                     pilotRunning: Bool = false, pilotInterrupted: Bool = false) -> ModSetOperations {
        ModSetOperations(bisectionRunning: bisectionRunning, bisectionInterrupted: bisectionInterrupted,
                         benchmarkRunning: benchmarkRunning, benchmarkInterrupted: benchmarkInterrupted,
                         pilotRunning: pilotRunning, pilotInterrupted: pilotInterrupted)
    }

    @Test("Rien en vol : rien ne bloque, rien à remettre")
    func idle() {
        #expect(ops().blocking == nil)
        #expect(ops().awaitingRestore.isEmpty)
    }

    @Test("Les interrompues, dans l'ordre fixe")
    func awaitingInOrder() {
        let o = ops(bisectionInterrupted: true, benchmarkInterrupted: false, pilotInterrupted: true)
        #expect(o.awaitingRestore == [.bisection, .pilot])
        #expect(o.blocking == .bisection)
    }

    @Test("Une opération en cours bloque avant une interrompue, et n'attend pas sa remise")
    func runningFirst() {
        let o = ops(bisectionInterrupted: true, benchmarkRunning: true, benchmarkInterrupted: true)
        #expect(o.blocking == .benchmark)
        #expect(o.awaitingRestore == [.bisection])
    }
}
