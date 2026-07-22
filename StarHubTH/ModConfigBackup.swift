import Foundation

/// A single mod's backed-up config files within a `ModConfigBackup`.
/// `parentFolderName` is set (display-only, for "part of group X" text) when
/// the mod is a child of a group pack (see `ModItem.isGroup`).
/// `modFolderName` is the mod's full path *relative to `Mods/`* — e.g.
/// "GroupFolder/ChildFolder" for a group child, or "PackFolder/ModX" for a
/// standalone mod nested in a subfolder — never just the trailing path
/// component, so restoring reconstructs the real on-disk location rather
/// than a flattened one.
struct ModConfigBackupItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let modFolderName: String
    let parentFolderName: String?
    let modDisplayName: String
    let files: [String]
    let fileSizes: [String: Int]
}

/// One backup pass: every enabled mod's `config.json`/`fr.json` files
/// captured at `timestamp`, stored under `folderName` in
/// `ModConfigBackupManager`'s backups directory.
struct ModConfigBackup: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let timestamp: Date
    let items: [ModConfigBackupItem]
    let totalFiles: Int
    let totalSize: Int
    /// The on-disk folder name under the backups directory. Stored
    /// explicitly (rather than recomputed from `timestamp`) so a UUID
    /// suffix can keep two backups created within the same second from
    /// colliding on one folder.
    var folderName: String

    enum CodingKeys: String, CodingKey {
        case id, timestamp, items, totalFiles, totalSize, folderName
    }

    init(id: UUID = UUID(), timestamp: Date, items: [ModConfigBackupItem], totalFiles: Int, totalSize: Int, folderName: String) {
        self.id = id
        self.timestamp = timestamp
        self.items = items
        self.totalFiles = totalFiles
        self.totalSize = totalSize
        self.folderName = folderName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        items = try container.decode([ModConfigBackupItem].self, forKey: .items)
        totalFiles = try container.decode(Int.self, forKey: .totalFiles)
        totalSize = try container.decode(Int.self, forKey: .totalSize)
        if let stored = try container.decodeIfPresent(String.self, forKey: .folderName) {
            folderName = stored
        } else {
            // Backups written before `folderName` existed used a
            // deterministic name derived purely from the timestamp.
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HHmmss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            folderName = "\(formatter.string(from: timestamp))_backup"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(items, forKey: .items)
        try container.encode(totalFiles, forKey: .totalFiles)
        try container.encode(totalSize, forKey: .totalSize)
        try container.encode(folderName, forKey: .folderName)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
}

/// On-disk index of every backup, persisted as `metadata.json`.
struct ModConfigBackupsIndex: Codable {
    var backups: [ModConfigBackup] = []
    var lastAutoCleanup: Date? = nil
}
