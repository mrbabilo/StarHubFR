import Foundation

/// Ce qu'une installation a posé — **figé** au moment du succès. La fenêtre
/// de bilan ne lit que ces données : un rafraîchissement du parc pendant la
/// lecture ne peut pas la faire diverger à l'écran.
public struct InstallReport: Equatable, Sendable {
    public let installedNames: [String]
    public let deltas: [ModUpdateKeyDelta]
    /// Les archives restant en file après celle qui vient de finir —
    /// « Archive suivante (n) » lit ce compte.
    public let remainingInQueue: Int

    public init(installedNames: [String], deltas: [ModUpdateKeyDelta],
                remainingInQueue: Int) {
        self.installedNames = installedNames
        self.deltas = deltas
        self.remainingInQueue = remainingInQueue
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

    public init(modsUpdated: Int, translationTodo: Int,
                configChanges: Int, renamesSuggested: Int) {
        self.modsUpdated = modsUpdated
        self.translationTodo = translationTodo
        self.configChanges = configChanges
        self.renamesSuggested = renamesSuggested
    }

    public static func of(_ deltas: [ModUpdateKeyDelta]) -> InstallReportSummary {
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
        return InstallReportSummary(modsUpdated: mods, translationTodo: todo,
                                    configChanges: config, renamesSuggested: renames)
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
