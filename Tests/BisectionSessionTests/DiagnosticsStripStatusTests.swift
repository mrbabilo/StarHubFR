import Testing
@testable import StarHubTHCore

/// D4-T4 §3a — ce que dit le bandeau en tête du Journal. Il remplace la carte
/// Santé et la bissection que la page affichait au-dessus des lignes : il ne
/// doit rien taire de ce qu'elles montraient (consigne « aucune perte »).
struct DiagnosticsStripStatusTests {
    private typealias Status = DiagnosticsStripStatus

    @Test func healthSaysNoLogHealthyOrProblems() {
        #expect(Status.health(hasLog: false, problemCount: 0) == .noLog)
        #expect(Status.health(hasLog: true, problemCount: 0) == .healthy)
        #expect(Status.health(hasLog: true, problemCount: 3) == .problems(3))
    }

    /// La carte montrait « Restaurer » pour une recherche coupée (plantage
    /// pendant un essai, mods restés en pause) : le bandeau doit le dire.
    @Test func anInterruptedSearchIsSaid() {
        #expect(Status.search(state: nil, hasInterruptedSnapshot: true, isApplying: false) == .interrupted)
    }

    @Test func aRunningSearchIsSaid() {
        #expect(Status.search(state: .reproducing, hasInterruptedSnapshot: false, isApplying: false) == .running)
        #expect(Status.search(state: .trial(step: 2, total: 5), hasInterruptedSnapshot: false, isApplying: false) == .running)
        #expect(Status.search(state: .confirming(folderName: "X"), hasInterruptedSnapshot: false, isApplying: false) == .running)
        // Démarrage en cours, avant le premier état.
        #expect(Status.search(state: nil, hasInterruptedSnapshot: false, isApplying: true) == .running)
    }

    /// Un coupable trouvé ou une recherche finie n'est pas « en cours ».
    @Test func aFinishedSearchSaysItsResultIsReady() {
        #expect(Status.search(state: .concluded(folderName: "X"), hasInterruptedSnapshot: false, isApplying: false) == .resultReady)
        #expect(Status.search(state: .inconclusive(remaining: ["A", "B"]), hasInterruptedSnapshot: false, isApplying: false) == .resultReady)
        #expect(Status.search(state: .notReproducible, hasInterruptedSnapshot: false, isApplying: false) == .resultReady)
    }

    @Test func noSearchSaysNothing() {
        #expect(Status.search(state: nil, hasInterruptedSnapshot: false, isApplying: false) == .none)
    }
}
