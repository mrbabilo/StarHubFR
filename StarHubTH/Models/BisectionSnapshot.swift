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
    /// Le dossier de stockage est un **paramètre**, plus un état de type.
    ///
    /// Deux choses en découlent. Deux tests concurrents ne peuvent plus se
    /// voler leur redirection : chacun donne le sien à l'appel. Et surtout,
    /// **aucun point d'entrée n'a de valeur par défaut** — il n'y a donc rien
    /// à oublier de rediriger, et aucune écriture ne peut retomber sur le vrai
    /// Application Support d'un joueur par inadvertance. La production, elle,
    /// passe explicitement `AppSupport.directory`.
    ///
    /// `nil` reste toléré en silence : le système ne rend aucun dossier de
    /// support, l'app ne peut de toute façon rien persister.
    private static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("bisection_snapshot.json")
    }

    public static func save(_ snapshot: BisectionSnapshot, in directory: URL?) {
        guard let directory, let data = try? JSONEncoder().encode(snapshot) else { return }
        let url = fileURL(in: directory)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // L'unique filet de récupération après crash : si l'écriture échoue
            // (disque plein, perms), la reprise sera impossible au prochain
            // démarrage. Le signaler plutôt que de l'avaler silencieusement.
            print("Warning: bisection snapshot write failed at \(url.path): \(error)")
        }
    }

    public static func load(from directory: URL?) -> BisectionSnapshot? {
        guard let directory,
              let data = try? Data(contentsOf: fileURL(in: directory)) else { return nil }
        return try? JSONDecoder().decode(BisectionSnapshot.self, from: data)
    }

    public static func clear(in directory: URL?) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: fileURL(in: directory))
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
    public static func finish(_ outcome: BisectionRestoreOutcome, in directory: URL?) -> Bool {
        guard outcome == .complete else { return false }
        clear(in: directory)
        return true
    }
}
