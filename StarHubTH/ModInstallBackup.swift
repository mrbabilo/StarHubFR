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
        formatter.locale = Locale(identifier: UserDefaults.standard.string(forKey: UDKey.currentLanguage) ?? "en")
        return formatter.string(from: timestamp)
    }
}

/// Ce qu'une restauration a écrit, et où.
///
/// La page n'annonçait qu'un « Sauvegarde restaurée avec succès » : ni le
/// dossier touché, ni l'état dans lequel le mod atterrit, ni le sort de la
/// version remplacée. Restaurer écrit dans `Mods/` — l'utilisateur doit
/// pouvoir vérifier ce qui a été fait sans ouvrir le Finder à l'aveugle.
public struct ModInstallRestoreReport: Sendable, Equatable {
    public let modName: String
    public let version: String
    /// Chemin absolu du dossier écrit — ce que le bouton « Afficher dans le
    /// Finder » révèle.
    public let destinationPath: String
    /// Le même chemin, relatif au dossier du jeu (`Mods/.Nom`) : ce qui se lit
    /// dans une phrase.
    public let displayPath: String
    /// Faux quand le mod atterrit en pause — SMAPI ne le chargera pas tant que
    /// l'utilisateur ne l'aura pas activé.
    public let landedEnabled: Bool
    /// Nombre de fichiers écrits.
    public let fileCount: Int
    /// Les versions mises de côté **et conservées** comme sauvegardes. Vide
    /// quand rien n'a été remplacé ; une version que l'archivage n'a pas pu
    /// retenir n'y figure pas, sous peine de promettre une sauvegarde
    /// inexistante.
    public let replacedVersions: [String]

    public init(modName: String,
                version: String,
                destinationPath: String,
                displayPath: String,
                landedEnabled: Bool,
                fileCount: Int,
                replacedVersions: [String]) {
        self.modName = modName
        self.version = version
        self.destinationPath = destinationPath
        self.displayPath = displayPath
        self.landedEnabled = landedEnabled
        self.fileCount = fileCount
        self.replacedVersions = replacedVersions
    }
}

/// On-disk index of every mod install backup, persisted as `install_metadata.json`
struct ModInstallBackupsIndex: Codable {
    var backups: [ModInstallBackup] = []
    var lastAutoCleanup: Date? = nil
}