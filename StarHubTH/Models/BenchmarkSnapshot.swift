import Foundation

/// Taille et date d'un fichier de sauvegarde **d'origine**, relevées avant la
/// série : le jeu ne charge que des copies, un écart après la série signale
/// une écriture inattendue.
public struct SaveFileStamp: Codable, Equatable, Sendable {
    public let path: String
    public let size: Int64
    public let modified: Date

    public init(path: String, size: Int64, modified: Date) {
        self.path = path
        self.size = size
        self.modified = modified
    }

    /// Nil si le fichier est absent ou illisible.
    public static func read(_ url: URL) -> SaveFileStamp? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            return nil
        }
        guard let size = (attributes[.size] as? NSNumber)?.int64Value,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return SaveFileStamp(path: url.path, size: size, modified: modified)
    }
}

public enum BenchmarkSaveCheck {
    /// Chemins dont la taille ou la date a changé, ou qui ont disparu. Dates
    /// comparées à la seconde : un aller-retour par les attributs n'est pas
    /// `==` au bit près (piège « Process, Pipe, système de fichiers »).
    public static func changed(_ originals: [SaveFileStamp]) -> [String] {
        originals.compactMap { stamp in
            guard let now = SaveFileStamp.read(URL(fileURLWithPath: stamp.path)) else { return stamp.path }
            let sameDate = abs(now.modified.timeIntervalSince(stamp.modified)) < 1
            return now.size == stamp.size && sameDate ? nil : stamp.path
        }
    }
}

/// L'état A d'un benchmark, écrit **avant** la première bascule : l'unique
/// filet de restauration si l'app plante en cours de série.
public struct BenchmarkSnapshot: Codable, Equatable, Sendable {
    public let enabledFolders: [String]
    public let activeProfileId: UUID?
    /// Chemins complets des dossiers de sauvegarde copiés pour la série, à
    /// mettre à la corbeille — même après un plantage de l'app.
    public let saveCopies: [String]
    public let originals: [SaveFileStamp]
    public let startedAt: Date

    public init(enabledFolders: [String], activeProfileId: UUID?, saveCopies: [String],
                originals: [SaveFileStamp], startedAt: Date) {
        self.enabledFolders = enabledFolders
        self.activeProfileId = activeProfileId
        self.saveCopies = saveCopies
        self.originals = originals
        self.startedAt = startedAt
    }
}

/// Même règle que `BisectionSnapshotStore` : le dossier est un paramètre sans
/// valeur par défaut — aucune écriture ne retombe par mégarde sur le vrai
/// Application Support ; la production passe `AppSupport.directory`.
public enum BenchmarkSnapshotStore {
    private static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("benchmark_snapshot.json")
    }

    /// Faux si l'instantané n'a pas pu être écrit : l'appelant refuse alors de
    /// basculer quoi que ce soit (pas de filet de restauration).
    @discardableResult
    public static func save(_ snapshot: BenchmarkSnapshot, in directory: URL?) -> Bool {
        guard let directory else { return false }
        do {
            try JSONEncoder().encode(snapshot).write(to: fileURL(in: directory), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func load(from directory: URL?) -> BenchmarkSnapshot? {
        guard let directory else { return nil }
        do {
            return try JSONDecoder().decode(BenchmarkSnapshot.self, from: Data(contentsOf: fileURL(in: directory)))
        } catch {
            return nil
        }
    }

    /// Faux si le fichier existe encore après la tentative.
    @discardableResult
    public static func clear(in directory: URL?) -> Bool {
        guard let directory else { return true }
        let url = fileURL(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }
}
