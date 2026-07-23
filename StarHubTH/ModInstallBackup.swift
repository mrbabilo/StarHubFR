import Foundation

/// Reason for creating a mod install backup
public enum BackupReason: String, Codable {
    case beforeInstall
    case beforeUpdate
    /// The live version set aside just before a backup was restored over
    /// it — registered as its own backup (rather than discarded) so
    /// restoring is itself undoable.
    case beforeRestore
}

/// Metadata about a mod extracted from manifest.json
public struct ModMetadata: Codable, Equatable {
    public let name: String
    public let version: String
    public let author: String
    public let uniqueId: String

    public init(name: String, version: String, author: String, uniqueId: String) {
        self.name = name
        self.version = version
        self.author = author
        self.uniqueId = uniqueId
    }
}

/// Backup of a complete mod folder before installation or update.
/// Stored in ~/Library/Application Support/StarHubTH/Backups/ModInstalls/
public struct ModInstallBackup: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public let timestamp: Date
    public let originalFolderName: String
    public let backupPath: String
    public let modMetadata: ModMetadata
    public let reason: BackupReason

    public init(id: UUID = UUID(), timestamp: Date, originalFolderName: String, backupPath: String, modMetadata: ModMetadata, reason: BackupReason) {
        self.id = id
        self.timestamp = timestamp
        self.originalFolderName = originalFolderName
        self.backupPath = backupPath
        self.modMetadata = modMetadata
        self.reason = reason
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        // Matches the app's selected language rather than the system
        // locale — same key StarHubTHViewModel.currentLanguage reads.
        formatter.locale = Locale(identifier: UserDefaults.standard.string(forKey: "currentLanguage") ?? "en")
        return formatter.string(from: timestamp)
    }
}

/// On-disk index of every mod install backup, persisted as `install_metadata.json`
struct ModInstallBackupsIndex: Codable {
    var backups: [ModInstallBackup] = []
    var lastAutoCleanup: Date? = nil
}