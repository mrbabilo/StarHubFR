import Foundation

/// R7 (audit UX 2026-10-16) — ouvrir les Réglages sur une section, depuis
/// n'importe quel écran. Fichier à part : `NavigationStore.swift` est au
/// plafond de 400 lignes.
extension NavigationStore {
    /// La section d'abord, l'onglet ensuite : `SettingsView` la consomme à
    /// son apparition (`showPendingSection`), patron `pending…Focus`.
    func openSettings(_ section: SettingsSection) {
        pendingSettingsSection = section
        requestTab(.settings)
    }
}
