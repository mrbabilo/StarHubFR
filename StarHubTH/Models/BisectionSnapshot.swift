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

/// Ce qu'a donné une remise en état : tous les dossiers ont-ils retrouvé leur
/// place ?
public enum BisectionRestoreOutcome: Equatable {
    case complete
    /// Au moins un dossier n'a pas pu être déplacé (jumeau `.Nom` déjà présent,
    /// dossier tenu ouvert par le Finder, Dropbox, un antivirus…).
    case partial(failedCount: Int)

    /// Construit le résultat à partir du nombre de déplacements en échec.
    ///
    /// Volontairement fondé sur les **échecs de déplacement seuls**, pas sur les
    /// mods introuvables : un dossier absent du disque ne sera pas davantage
    /// retrouvé au prochain essai, et garder l'instantané pour lui ferait
    /// reproposer indéfiniment une reprise qui ne peut pas aboutir.
    public init(moveFailures: Int) {
        self = moveFailures == 0 ? .complete : .partial(failedCount: moveFailures)
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
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // L'unique filet de récupération après crash : si l'écriture échoue
            // (disque plein, perms), la reprise sera impossible au prochain
            // démarrage. Le signaler plutôt que de l'avaler silencieusement.
            print("Warning: bisection snapshot write failed at \(url.path): \(error)")
        }
    }

    public static func load() -> BisectionSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BisectionSnapshot.self, from: data)
    }

    public static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Referme une recherche après une remise en état.
    ///
    /// L'instantané n'est oublié que si **tous** les dossiers ont retrouvé leur
    /// place. S'il en reste un en pause, l'effacer supprimerait la seule trace
    /// de l'état de départ : la modlist resterait à moitié en pause sans moyen
    /// de la retrouver. Tant qu'il subsiste, la remise en état reste
    /// réessayable — au prochain démarrage s'il le faut.
    ///
    /// - Returns: `true` si l'instantané a été oublié. L'appelant doit
    ///   conditionner la remise à zéro de son état mémoire à cette valeur, pour
    ///   que disque et mémoire ne puissent jamais diverger.
    @discardableResult
    public static func finish(_ outcome: BisectionRestoreOutcome) -> Bool {
        guard outcome == .complete else { return false }
        clear()
        return true
    }
}
