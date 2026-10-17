import Testing
@testable import StarHubTHCore

/// P5-5a — un dépôt sur la fenêtre ne s'ouvre que là où il ne recouvre rien.
struct ArchiveDropRefusalTests {

    private func operations(bisection: Bool = false, benchmark: Bool = false, pilot: Bool = false,
                            interrupted: Bool = false) -> ModSetOperations {
        ModSetOperations(bisectionRunning: bisection, bisectionInterrupted: interrupted,
                         benchmarkRunning: benchmark, benchmarkInterrupted: interrupted,
                         pilotRunning: pilot, pilotInterrupted: interrupted)
    }

    private func refusal(installOpen: Bool = false, downloadBusy: Bool = false,
                         profileApplying: Bool = false,
                         operations: ModSetOperations? = nil) -> ArchiveDropRefusal? {
        ArchiveDropRefusal.first(installOpen: installOpen, downloadBusy: downloadBusy,
                                 profileApplying: profileApplying,
                                 operations: operations ?? self.operations())
    }

    @Test func nothingRunningAcceptsTheDrop() {
        #expect(refusal() == nil)
    }

    /// Une opération interrompue attend sa remise ; installer n'y touche pas.
    @Test func anInterruptedOperationDoesNotRefuse() {
        #expect(refusal(operations: operations(interrupted: true)) == nil)
    }

    @Test func eachBusyStateRefusesOnItsOwn() {
        #expect(refusal(installOpen: true) == .installOpen)
        #expect(refusal(downloadBusy: true) == .downloadBusy)
        #expect(refusal(profileApplying: true) == .profileApplying)
        #expect(refusal(operations: operations(bisection: true)) == .operationRunning(.bisection))
        #expect(refusal(operations: operations(benchmark: true)) == .operationRunning(.benchmark))
        #expect(refusal(operations: operations(pilot: true)) == .operationRunning(.pilot))
    }

    /// L'ouverte d'abord : c'est là que l'utilisateur doit déposer.
    @Test func anOpenInstallSheetIsNamedFirst() {
        #expect(refusal(installOpen: true, downloadBusy: true, profileApplying: true,
                        operations: operations(bisection: true)) == .installOpen)
    }
}
