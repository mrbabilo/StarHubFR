import Foundation

/// A1-T11 — le journal local d'un mod : chaque installation, mise à jour,
/// ajout déposé par l'app et nettoyage, avec les fichiers en cause.
///
/// C'est à la fois ce que la fiche du mod montre et la **référence** de la
/// mise à jour suivante : les fichiers qu'une installation a posés depuis
/// l'archive disent exactement ce que l'auteur livrait — y compris pour les
/// 67 % de mods dont Nexus n'a que des manifestes sans empreintes (mesuré le
/// 2026-09-27).
public struct ModHistory: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case install, update, addition, cleanup
    }

    public struct File: Codable, Equatable, Sendable {
        public let path: String
        public let size: Int64
        public let sha256: String

        public init(path: String, size: Int64, sha256: String) {
            self.path = path
            self.size = size
            self.sha256 = sha256
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public let date: Date
        public let kind: Kind
        public let fromVersion: String?
        public let toVersion: String?
        /// SHA-256 de l'archive installée : identifie le fichier Nexus même
        /// quand l'installation n'a pas lu Nexus (glisser-déposer).
        public let archiveSHA256: String?
        public let nexusFileId: Int?
        /// Nom de l'archive, ou de ce qui a été déposé (« traduction X »).
        public let source: String?
        /// Installation/mise à jour : les fichiers **de l'archive**. Ajout :
        /// les fichiers déposés. Nettoyage : les fichiers retirés.
        public let files: [File]
        public let report: UpdateTriageReport?

        public init(date: Date, kind: Kind, fromVersion: String?, toVersion: String?,
                    archiveSHA256: String?, nexusFileId: Int?, source: String?,
                    files: [File], report: UpdateTriageReport?) {
            self.date = date
            self.kind = kind
            self.fromVersion = fromVersion
            self.toVersion = toVersion
            self.archiveSHA256 = archiveSHA256
            self.nexusFileId = nexusFileId
            self.source = source
            self.files = files
            self.report = report
        }
    }

    public let uniqueId: String
    public private(set) var entries: [Entry]

    public init(uniqueId: String, entries: [Entry] = []) {
        self.uniqueId = uniqueId
        self.entries = entries
    }

    public mutating func append(_ entry: Entry) {
        entries.append(entry)
    }

    /// Les installations et mises à jour, comme versions d'auteur (clés
    /// normalisées), dans l'ordre du journal — la dernière est la référence
    /// quand sa version est celle installée.
    public var authorVersions: [AuthorFileIndex.Version] {
        entries.compactMap { entry in
            guard entry.kind == .install || entry.kind == .update,
                  let version = entry.toVersion else { return nil }
            var files: [String: String] = [:]
            for file in entry.files { files[ModFilePath.key(file.path)] = file.sha256 }
            return AuthorFileIndex.Version(source: .localHistory, version: version, files: files)
        }
    }

    /// Clés des fichiers que l'app a déposés chez ce mod (règle 2).
    public var depositedKeys: Set<String> {
        Set(entries.filter { $0.kind == .addition }.flatMap { $0.files.map { ModFilePath.key($0.path) } })
    }

    /// Les fichiers d'un listage, pour une entrée.
    public static func files(of listing: ModFolderHasher.Listing) -> [File] {
        listing.hashes.keys.sorted().map {
            File(path: $0, size: listing.sizes[$0] ?? 0, sha256: listing.hashes[$0] ?? "")
        }
    }
}

/// Le journal sur disque : `Application Support/StarHubFR/ModHistory/<UniqueID>.json`.
///
/// Jamais par nom de dossier ni par id Nexus : 58 id Nexus sont partagés
/// entre mods distincts sur le parc.
public enum ModHistoryFile {
    public enum Loaded: Equatable, Sendable {
        case missing
        case unreadable
        case history(ModHistory)
    }

    public static func defaultDirectory() -> URL? {
        AppSupport.directory?.appendingPathComponent("ModHistory", isDirectory: true)
    }

    static func url(uniqueId: String, directory: URL) -> URL {
        directory.appendingPathComponent("\(uniqueId).json")
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func load(uniqueId: String, directory: URL?) -> Loaded {
        guard let directory, !uniqueId.isEmpty,
              let data = FileManager.default.contents(atPath: url(uniqueId: uniqueId, directory: directory).path)
        else { return .missing }
        do {
            return .history(try decoder().decode(ModHistory.self, from: data))
        } catch {
            return .unreadable
        }
    }

    /// Le journal du mod, vide s'il n'existe pas ou ne se lit plus.
    public static func history(uniqueId: String, directory: URL?) -> ModHistory {
        if case .history(let history) = load(uniqueId: uniqueId, directory: directory) { return history }
        return ModHistory(uniqueId: uniqueId)
    }

    /// Ajoute une entrée. Un journal illisible n'est **jamais écrasé** : il
    /// est mis de côté (`<UniqueID>.unreadable-<date>.json`) et un journal neuf
    /// commence — sinon un fichier abîmé effacerait tout l'historique à la
    /// première installation venue.
    public static func append(_ entry: ModHistory.Entry, uniqueId: String, directory: URL?,
                              now: Date = Date()) throws {
        guard let directory, !uniqueId.isEmpty else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = url(uniqueId: uniqueId, directory: directory)
        var history: ModHistory
        switch load(uniqueId: uniqueId, directory: directory) {
        case .history(let existing):
            history = existing
        case .missing:
            history = ModHistory(uniqueId: uniqueId)
        case .unreadable:
            let stamp = Int(now.timeIntervalSince1970)
            try fm.moveItem(at: target,
                            to: directory.appendingPathComponent("\(uniqueId).unreadable-\(stamp).json"))
            history = ModHistory(uniqueId: uniqueId)
        }
        history.append(entry)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(history).write(to: target, options: .atomic)
    }
}
