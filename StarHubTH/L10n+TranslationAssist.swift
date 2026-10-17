/// N-11 (audit UX 2026-10-16) — le remède d'un refus de l'aide à la
/// traduction. Fichier à part : `L10n.swift` est verrouillé par le cliquet
/// de taille.
extension L10n {
    enum TranslationAssist {
        static let openSettings = "translation_assist_open_settings"
        static let saveFirst = "translation_assist_save_first"
    }
}

extension LocalizationStore {
    /// Le message d'un refus de l'aide et son réglage (`TranslationAssistFailure`).
    func notice(_ failure: TranslationAssistFailure) -> TranslationEditorNotice {
        .init(text: self.L(failure.messageKey), settings: failure.settings)
    }
}

/// N-11 — la note « traduction dans une sauvegarde » de la fiche et le filtre
/// des Fichiers récupérables qu'elle pose.
extension L10n.Recovery {
    static let openFromDetail = "recovery_open_from_detail"
    static let filteredOn = "recovery_filtered_on"
    static let showAll = "recovery_show_all"
}
