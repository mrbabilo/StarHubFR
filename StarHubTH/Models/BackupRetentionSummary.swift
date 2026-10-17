import Foundation

/// R1 (audit UX 2026-10-16) — la règle de rétention automatique des
/// sauvegardes d'installation, dite par un seul type à partir des constantes
/// de `ModInstallBackupManager.cleanupOldBackups` : le segment Installations
/// et l'Entretien la disaient sous deux formes, sans rien qui les relie.
public enum BackupRetentionSummary {
    /// La fenêtre où tout est gardé, en jours.
    public static var days: Int { Int(ModInstallBackupManager.maxBackupAge / 86_400) }
    /// Les plus récentes, gardées quel que soit leur âge.
    public static var minimumKept: Int { ModInstallBackupManager.minBackupsToKeep }

    public static func automatic(localized localize: (String) -> String) -> String {
        String(format: localize(L10n.ModInstall.retentionPolicy), Int64(days), Int64(minimumKept))
    }
}
