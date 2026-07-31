import Foundation

/// L'état activé au moment où la recherche commence.
///
/// Écrit sur disque **avant le moindre déplacement de dossier** : StarHubFR peut
/// être quitté ou planter en cours de route, et sans cet instantané l'utilisateur
/// se retrouverait avec une modlist à moitié en pause sans savoir laquelle était
/// la sienne.
public struct BisectionSnapshot: Codable, Equatable {
    public let enabledFolders: [String]
    public let startedAt: Date

    public init(enabledFolders: [String], startedAt: Date) {
        self.enabledFolders = enabledFolders
        self.startedAt = startedAt
    }
}

public enum BisectionSnapshotStore {
    /// Dossier où vit l'instantané. Par défaut, le même Application Support que
    /// le reste de l'état de diagnostic, pour qu'un seul endroit concentre la
    /// récupération après coup. `internal` et mutable uniquement pour les tests,
    /// qui le redirigent vers un dossier temporaire afin de ne jamais risquer
    /// l'instantané réel d'une recherche laissée en plan.
    static var storageDirectory: URL? = defaultDirectory()

    private static func defaultDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("StarHubTH", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL? {
        storageDirectory?.appendingPathComponent("bisection_snapshot.json")
    }

    public static func save(_ snapshot: BisectionSnapshot) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func load() -> BisectionSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BisectionSnapshot.self, from: data)
    }

    public static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
