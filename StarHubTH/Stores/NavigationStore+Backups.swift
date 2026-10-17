import Foundation

/// R1 (audit UX 2026-10-16) — les renvois entre l'Entretien et « Sauvegardes
/// des mods », dans les deux sens. Fichier à part : `NavigationStore.swift`
/// est au plafond de 400 lignes.
extension NavigationStore {
    /// Un segment de Sauvegardes, sans filtre : la légende de stockage de
    /// l'Entretien.
    func openBackups(segment: BackupsSegment) {
        backupsSegment = segment
        requestTab(.backups)
    }

    /// L'Entretien : « Libérer de la place » et la corbeille des mods, depuis
    /// Sauvegardes.
    func openMaintenance() {
        requestTab(.maintenance)
    }
}
