/// « Nettoyer les anciens fichiers » quand l'historique Nexus au format ancien
/// ne se lit plus (relevé des sources du 2026-11-11). Fichier à part :
/// `L10n.swift` est verrouillé par le cliquet de taille.
extension L10n.ModCleanup {
    static let legacyUnreadable  = "mod_cleanup_legacy_unreadable"
    static let legacyNoReference = "mod_cleanup_legacy_no_reference"
}
