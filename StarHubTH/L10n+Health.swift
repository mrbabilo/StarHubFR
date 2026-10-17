/// R2 (audit UX 2026-10-16) — les renvois entre Alertes et Santé, et le
/// journal SMAPI dont les deux pages dérivent. Fichier à part : `L10n.swift`
/// est verrouillé par le cliquet de taille.
extension L10n.Health {
    /// E8 — l'en-tête des Alertes au pluriel juste (`plural`, clé `_one`).
    static let problems = "health_problems"
    static let criticals = "health_criticals"
    static let logSource = "alerts_log_source"
    static let logStaleAge = "alerts_log_stale_age"
    static let logOpenHealth = "alerts_log_open_health"
    /// Au pluriel par `LocalizationStore.plural` (clé `_one` pour 1).
    static let openAlerts = "health_open_alerts"
    static let openAlertsAction = "health_open_alerts_action"
}
