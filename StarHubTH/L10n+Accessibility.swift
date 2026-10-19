extension L10n {
    /// Titres lus par VoiceOver sur des contrôles dont le libellé est masqué
    /// (`labelsHidden`) : sans eux, VoiceOver lit les segments mais pas ce
    /// qu'ils choisissent (relevé d'accessibilité du 2026-10-19).
    enum A11y {
        static let installConflictChoice = "a11y_install_conflict_choice"
        static let detailTabs = "a11y_detail_tabs"
        static let alertsSegment = "a11y_alerts_segment"
        static let lotDecision = "a11y_lot_decision"
        static let frTranslationsList = "a11y_fr_translations_list"
        static let configEditorMode = "a11y_config_editor_mode"
        static let keybindFilter = "a11y_keybind_filter"
        static let backupsSegment = "a11y_backups_segment"
        static let diagnosticsSegment = "a11y_diagnostics_segment"
        static let configBackupsGrouping = "a11y_config_backups_grouping"
        static let translationUpdateChoice = "a11y_translation_update_choice"
        static let loadDetail = "a11y_load_detail"
        static let keybindPlanInclude = "a11y_keybind_plan_include"
    }
}
