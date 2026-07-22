import Foundation

/// Reason for creating a mod install backup
enum BackupReason: String, Codable {
    case beforeInstall
    case beforeUpdate
    /// The live version set aside just before a backup was restored over
    /// it — registered as its own backup (rather than discarded) so
    /// restoring is itself undoable.
    case beforeRestore
}

/// Metadata about a mod extracted from manifest.json
struct ModMetadata: Codable, Equatable {
    let name: String
    let version: String
    let author: String
    let uniqueId: String
}

/// Backup of a complete mod folder before installation or update.
/// Stored in ~/Library/Application Support/StarHubTH/Backups/ModInstalls/
struct ModInstallBackup: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let timestamp: Date
    let originalFolderName: String
    let backupPath: String
    let modMetadata: ModMetadata
    let reason: BackupReason
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

/// On-disk index of every mod install backup, persisted as `install_metadata.json`
struct ModInstallBackupsIndex: Codable {
    var backups: [ModInstallBackup] = []
    var lastAutoCleanup: Date? = nil
}