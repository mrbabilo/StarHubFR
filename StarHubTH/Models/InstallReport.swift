import Foundation

/// Ce qu'une installation a posé — **figé** au moment du succès. La fenêtre
/// de bilan ne lit que ces données : un rafraîchissement du parc pendant la
/// lecture ne peut pas la faire diverger à l'écran.
/// A1-T7 — ce qu'une mise à jour a remis en place pour **un** mod : les
/// fichiers que le mod avait écrits en jouant et que l'archive neuve ne livre
/// pas (`<sauvegarde>_SaveData.save` et apparentés).
///
/// `failed` porte les **noms**, pas un compte : c'est le seul cas où
/// l'utilisateur a quelque chose à faire — le fichier dort dans la sauvegarde
/// d'installation, et sans son nom il ne sait pas quoi y rechercher.
public struct PreservedDataOutcome: Equatable, Sendable {
    public let modFolder: String
    public let restored: Int
    public let failed: [String]
    /// A1-T7 (suite) — les chemins remis, pour que le bilan **nomme** ce
    /// qu'il a replacé, et pas seulement compté.
    public let paths: [String]
    /// L'option de non-remise (réglage global) : fichiers préservés puis
    /// laissés dans la sauvegarde d'installation, par choix de l'utilisateur.
    public let skipped: Int

    public init(modFolder: String, restored: Int, failed: [String],
                paths: [String] = [], skipped: Int = 0) {
        self.modFolder = modFolder
        self.restored = restored
        self.failed = failed
        self.paths = paths
        self.skipped = skipped
    }

    /// Rien à dire quand rien n'a été touché — le bilan ne doit pas bavarder
    /// sur une installation ordinaire. Des données **non remises par choix**
    /// ne sont pas muettes : l'utilisateur doit savoir où elles dorment.
    public var isSilent: Bool { restored == 0 && failed.isEmpty && skipped == 0 }
}

public struct InstallReport: Equatable, Sendable {
    public let installedNames: [String]
    public let deltas: [ModUpdateKeyDelta]
    /// A1-T7 — les données de mod remises en place, mod par mod. Vide quand
    /// l'installation n'a rien préservé.
    public let preserved: [PreservedDataOutcome]
    /// Les archives restant en file après celle qui vient de finir —
    /// « Archive suivante (n) » lit ce compte.
    public let remainingInQueue: Int

    public init(installedNames: [String], deltas: [ModUpdateKeyDelta],
                remainingInQueue: Int,
                preserved: [PreservedDataOutcome] = []) {
        self.installedNames = installedNames
        self.deltas = deltas
        self.remainingInQueue = remainingInQueue
        self.preserved = preserved.filter { !$0.isSilent }
    }
}

/// Le bilan chiffré en tête de fenêtre, agrégé depuis les mêmes données que
/// les lignes de delta — jamais un second parcours approximatif.
public struct InstallReportSummary: Equatable, Sendable {
    public let modsUpdated: Int
    /// Les clés réellement à traduire : les renommages suggérés en sortent —
    /// ils ont leur propre compteur. Les lignes de delta, elles, affichent
    /// les comptes bruts (comportement C2-T4 conservé).
    public let translationTodo: Int
    public let configChanges: Int
    public let renamesSuggested: Int
    /// A1-T7 — fichiers de données du mod remis en place, et ceux qui ont
    /// résisté. Deux compteurs distincts : le second n'est pas un sous-cas du
    /// premier, et c'est lui qui appelle une action.
    public let dataRestored: Int
    public let dataFailed: Int

    public init(modsUpdated: Int, translationTodo: Int,
                configChanges: Int, renamesSuggested: Int,
                dataRestored: Int = 0, dataFailed: Int = 0) {
        self.modsUpdated = modsUpdated
        self.translationTodo = translationTodo
        self.configChanges = configChanges
        self.renamesSuggested = renamesSuggested
        self.dataRestored = dataRestored
        self.dataFailed = dataFailed
    }

    public static func of(_ deltas: [ModUpdateKeyDelta],
                          preserved: [PreservedDataOutcome] = []) -> InstallReportSummary {
        var mods = 0, todo = 0, config = 0, renames = 0
        for d in deltas {
            mods += 1
            config += (d.config?.added.count ?? 0) + (d.config?.removed.count ?? 0)
            let renamed = KeyRenameMatcher.pairsByValue(
                old: d.translation.removedKeys,
                new: d.translation.addedUntranslated)
            renames += renamed.count
            todo += d.translation.addedUntranslated.count - renamed.count
        }
        return InstallReportSummary(
            modsUpdated: mods, translationTodo: todo,
            configChanges: config, renamesSuggested: renames,
            dataRestored: preserved.reduce(0) { $0 + $1.restored },
            dataFailed: preserved.reduce(0) { $0 + $1.failed.count })
    }
}

/// La file de dépôt multiple — migrée du `@State` de la feuille au
/// ViewModel pour que le chaînage survive à la fermeture de la feuille
/// (la fenêtre de bilan vit entre deux zips).
public struct InstallDropQueue: Equatable, Sendable {
    private(set) var urls: [URL]

    public init(urls: [URL] = []) { self.urls = urls }
    public var current: URL? { urls.first }
    public var count: Int { urls.count }
    public var isEmpty: Bool { urls.isEmpty }

    public mutating func push(_ new: [URL]) { urls.append(contentsOf: new) }

    /// Consomme l'archive courante ; la rend pour traçabilité, `nil` si vide.
    @discardableResult
    public mutating func advance() -> URL? {
        guard !urls.isEmpty else { return nil }
        return urls.removeFirst()
    }
}
