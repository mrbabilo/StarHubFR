/// R5 (audit UX 2026-10-16) — l'encart « Opération interrompue » de l'Accueil
/// et la porte vers « Revenir à un état d'avant » depuis le menu ⏻. Fichier
/// à part : `L10n.swift` est verrouillé par le cliquet de taille.
extension L10n {
    enum Interrupted {
        static let title = "interrupted_title"
        static let body = "interrupted_body"
        static let rowBisection = "interrupted_row_bisection"
        static let rowBenchmark = "interrupted_row_benchmark"
        static let rowPilot = "interrupted_row_pilot"
    }
}

extension L10n.ActivationHistory {
    static let menuEntry = "activation_history_menu_entry"
    static let blocked = "activation_history_blocked"
    static let gestureBisection = "activation_history_gesture_bisection"
    static let gestureBenchmark = "activation_history_gesture_benchmark"
}

extension LocalizationStore {
    /// Le nom d'une opération qui tient le parc (encart, infobulle de garde).
    func name(of operation: ModSetOperations.Operation) -> String {
        switch operation {
        case .bisection: return self.L(L10n.Interrupted.rowBisection)
        case .benchmark: return self.L(L10n.Interrupted.rowBenchmark)
        case .pilot: return self.L(L10n.Interrupted.rowPilot)
        }
    }
}
