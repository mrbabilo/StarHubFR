import Foundation

/// D4-T4 §3a — ce que dit le bandeau en tête du Journal de « Diagnostic &
/// Performances ». Il remplace la carte Santé et la bissection que la page
/// affichait au-dessus des lignes : il ne doit rien taire de ce qu'elles
/// montraient (consigne de l'auteur, 2026-09-28 : aucune perte).
public enum DiagnosticsStripStatus {
    public enum Health: Equatable, Sendable {
        case noLog
        case healthy
        case problems(Int)
    }

    /// La recherche guidée du mod responsable, vue du bandeau.
    public enum Search: Equatable, Sendable {
        case none
        /// Coupée (l'app s'est arrêtée pendant un essai) : des mods sont
        /// restés en pause, la carte propose « Restaurer ».
        case interrupted
        case running
        /// Un coupable trouvé, ou une recherche finie sans lui : le résultat
        /// attend sur l'onglet Santé.
        case resultReady
    }

    public static func health(hasLog: Bool, problemCount: Int) -> Health {
        guard hasLog else { return .noLog }
        return problemCount == 0 ? .healthy : .problems(problemCount)
    }

    public static func search(state: BisectionState?, hasInterruptedSnapshot: Bool,
                              isApplying: Bool) -> Search {
        switch state {
        case .reproducing, .trial, .confirming:
            return .running
        case .concluded, .inconclusive, .notReproducible:
            return .resultReady
        case nil:
            if isApplying { return .running }
            return hasInterruptedSnapshot ? .interrupted : .none
        }
    }
}
