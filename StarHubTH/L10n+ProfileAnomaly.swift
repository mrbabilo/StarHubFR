/// P5-9 (audit UX 2026-10-16) — les pastilles d'état anormal d'un profil.
/// Fichier à part : `L10n.swift` est verrouillé par le cliquet de taille.
extension L10n {
    enum ProfileAnomaly {
        static let interrupted = "profile_anomaly_interrupted"
        static let interruptedAction = "profile_anomaly_interrupted_action"
        static let interruptedHelp = "profile_anomaly_interrupted_help"
        static let incomplete = "profile_anomaly_incomplete"
        static let incompleteAction = "profile_anomaly_incomplete_action"
        static let incompleteHelp = "profile_anomaly_incomplete_help"
        static let desync = "profile_anomaly_desync"
        static let desyncAction = "profile_anomaly_desync_action"
        static let desyncHelp = "profile_anomaly_desync_help"
        static let desyncGameRunning = "profile_anomaly_desync_game_running"
    }
}
