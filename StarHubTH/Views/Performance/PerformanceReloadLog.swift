import Foundation

/// Diagnostic du 2026-10-14 (« l'onglet Performances se rafraîchit très
/// souvent hors mesure », non reproduit) : chaque relecture de l'onglet
/// laisse une ligne au journal, avec sa cause et sa durée — la prochaine
/// occurrence dit quel déclencheur tire, au lieu de le deviner.
enum PerformanceReloadLog {
    @MainActor
    static func run(_ viewModel: StarHubTHViewModel, cause: String, _ work: () async -> Void) async {
        let clock = ContinuousClock()
        let start = clock.now
        await work()
        let seconds = (clock.now - start) / .seconds(1)
        viewModel.log(String(format: "Performances : relecture (%@) en %.1f s.", cause, seconds))
    }
}
