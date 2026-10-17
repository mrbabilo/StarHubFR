/// P5-5a (audit UX 2026-10-16) — le bandeau du dépôt d'archive sur la
/// fenêtre. Fichier à part : `L10n.swift` est verrouillé par le cliquet de
/// taille.
extension L10n {
    enum ArchiveDrop {
        static let hint = "archive_drop_hint"
        static let refusedInstallOpen = "archive_drop_refused_install_open"
        static let refusedDownload = "archive_drop_refused_download"
        static let refusedProfile = "archive_drop_refused_profile"
        static let refusedOperation = "archive_drop_refused_operation"
    }
}
