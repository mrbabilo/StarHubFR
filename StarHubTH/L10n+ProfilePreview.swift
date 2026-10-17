/// P5-1 (audit UX 2026-10-16) — l'aperçu d'un profil dans sa feuille. Fichier
/// à part : `L10n.swift` est verrouillé par le cliquet de taille.
extension L10n {
    enum ProfilePreview {
        static let section = "profile_preview_section"
        static let readOnly = "profile_preview_read_only"
        static let nothing = "profile_preview_nothing"
        static let scanning = "profile_preview_scanning"
        static let toEnable = "profile_preview_to_enable"
        static let toDisable = "profile_preview_to_disable"
        static let conflicts = "profile_preview_conflicts"
        static let menuEntry = "profile_preview_menu_entry"
        static let columnHelp = "profile_preview_column_help"
    }
}

/// N-12 — le sous-titre d'un profil dans la palette.
extension L10n.Palette {
    static let profileHint = "palette_profile_hint"
}
