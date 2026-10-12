/// P1 — la mesure pilotée (paire guidée jouée d'un clic). Fichier à part :
/// `L10n.swift` est verrouillé par le cliquet de taille.
extension L10n {
    enum PerformancePilot {
        static let locked = "perf_pilot_locked"
        static let action = "perf_pilot_action"
        static let actionHelp = "perf_pilot_action_help"
        static let profileNote = "perf_pilot_profile_note"
        static let status = "perf_pilot_status"
        static let stepBefore = "perf_pilot_step_before"
        static let stepAfter = "perf_pilot_step_after"
        static let applying = "perf_pilot_applying"
        static let failedNoMeasurement = "perf_pilot_failed_noMeasurement"
        static let failedStalled = "perf_pilot_failed_stalled"
        static let failedApplyFailed = "perf_pilot_failed_applyFailed"
        static let failedRevertFailed = "perf_pilot_failed_revertFailed"
        static let failedGameQuit = "perf_pilot_failed_gameQuit"
        static let failedStopped = "perf_pilot_failed_stopped"
        static let interrupted = "perf_pilot_interrupted"
        static let ready = "perf_pilot_ready"
        static let rollback = "perf_pilot_rollback"
        static let rollbackHelp = "perf_pilot_rollback_help"
        static let rollbackFailed = "perf_pilot_rollback_failed"
        static let dismiss = "perf_pilot_dismiss"
        static let stop = "perf_pilot_stop"
        static let stopHelp = "perf_pilot_stop_help"
        static let startRefused = "perf_pilot_start_refused"
        static let noSave = "perf_pilot_no_save"
        static let needProfile = "perf_pilot_need_profile"
        static let resume = "perf_pilot_resume"
        static let resumeHelp = "perf_pilot_resume_help"
        static let notPersisted = "perf_pilot_not_persisted"
        static let needsProbeUpdate = "perf_pilot_needs_probe_update"
        static let refSeries = "perf_pilot_ref_series"
        static let refBenchmark = "perf_pilot_ref_benchmark"
        static let refBisection = "perf_pilot_ref_bisection"
        static let refSlo = "perf_pilot_ref_slo"
        static let refStardropium = "perf_pilot_ref_stardropium"
        static let refModsBusy = "perf_pilot_ref_mods_busy"
        static let refManualPlan = "perf_pilot_ref_manual_plan"
        static let refPlan = "perf_pilot_ref_plan"
        static let refLaunch = "perf_pilot_ref_launch"
    }
}

/// P2 — « Benchmarker ce mod » (L10n.swift verrouillé par le cliquet).
extension L10n.Performance {
    static let benchmarkThisMod = "perf_benchmark_this_mod"
}
