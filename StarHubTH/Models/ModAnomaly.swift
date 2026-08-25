import Foundation

/// Ce qui empêche un mod de bien tourner, résumé pour sa ligne de liste.
///
/// Trois signaux, réunis parce qu'ils répondent à la même question — « lequel
/// de ces 863 mods dois-je regarder » — et qu'une seule pastille vaut mieux que
/// trois qui se disputent la place.
public struct ModAnomaly: Equatable {
    public enum Severity: Equatable {
        /// Le mod ne tourne pas, ou a réellement échoué : erreurs relevées sur
        /// la version installée, dépendance requise absente, manifeste que SMAPI
        /// ne saura pas charger.
        case error
        /// Le mod tourne, mais se plaint.
        case warning
    }

    public let severity: Severity
    /// Erreurs relevées **sur la version installée** (voir `count(of:)`).
    public let errorCount: Int
    public let warningCount: Int
    /// Une dépendance requise manque, ou est présente mais en pause.
    public let hasDependencyIssue: Bool
    /// Le manifeste n'annonce aucun `UniqueID` : SMAPI ne chargera pas ce mod.
    public let isUnloadable: Bool

    public init(severity: Severity, errorCount: Int, warningCount: Int,
                hasDependencyIssue: Bool, isUnloadable: Bool) {
        self.severity = severity
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.hasDependencyIssue = hasDependencyIssue
        self.isUnloadable = isUnloadable
    }

    /// Ce que la pastille affiche : le nombre d'incidents, ou rien quand
    /// l'anomalie n'est pas comptable (dépendance, manifeste).
    public var badgeCount: Int { errorCount + warningCount }
}

public enum ModAnomalyReport {
    /// Résume l'état d'un mod, `nil` quand il n'y a rien à signaler.
    ///
    /// **Les compteurs ne portent que sur la version installée.** Additionner
    /// les versions ferait dire à la liste le contraire de ce que la fiche du
    /// mod affirme — elle rend l'historique version par version, précisément
    /// parce que « le compte d'une vieille version n'est pas ce que le joueur
    /// exécute aujourd'hui ». Mesuré sur le parc réel : un mod totalisait 76
    /// erreurs, dont **une seule** sur la version installée ; les 75 autres
    /// appartenaient à une version remplacée depuis, et la pastille aurait
    /// crié pour un problème déjà réglé.
    ///
    /// - Parameters:
    ///   - mod: la ligne de liste — mod autonome, en-tête de pack ou composant.
    ///   - history: l'historique accumulé depuis les journaux SMAPI, indexé sur
    ///     le `folderName` **logique**.
    ///   - dependencyIssue: la règle de dépendance, **passée** plutôt que
    ///     réécrite : la liste en a déjà une pour son cadrage « Problèmes », et
    ///     deux définitions de « ce mod a un problème » finiraient par ne plus
    ///     dire la même chose.
    public static func anomaly(for mod: ModItem,
                               history: ModErrorHistory,
                               dependencyIssue: (ModItem) -> Bool) -> ModAnomaly? {
        // Un en-tête de pack porte l'anomalie de ses composants : sans ça, il
        // faudrait déplier chaque pack pour découvrir lequel pose problème. Les
        // composants gardent la leur — contrairement au poids, une erreur
        // s'attribue à un composant précis, elle ne se compte pas deux fois.
        let subjects = [mod] + (mod.children ?? [])

        var errors = 0
        var warnings = 0
        var dependency = false
        var unloadable = false

        for subject in subjects {
            let counts = countsForInstalledVersion(of: subject, in: history)
            errors += counts.errors
            warnings += counts.warnings
            if dependencyIssue(subject) { dependency = true }
            // Un en-tête de pack n'a **jamais** d'`UniqueID` : c'est sa nature,
            // pas une anomalie. Le tester le signalerait tous.
            if !subject.isGroup, subject.uniqueId.isEmpty { unloadable = true }
        }

        if errors > 0 || dependency || unloadable {
            return ModAnomaly(severity: .error, errorCount: errors, warningCount: warnings,
                              hasDependencyIssue: dependency, isUnloadable: unloadable)
        }
        if warnings > 0 {
            return ModAnomaly(severity: .warning, errorCount: 0, warningCount: warnings,
                              hasDependencyIssue: false, isUnloadable: false)
        }
        return nil
    }

    /// Les incidents relevés pour la version que porte le mod aujourd'hui.
    /// Rien quand l'historique ne connaît que des versions antérieures — le
    /// mod a été mis à jour depuis, le problème appartient au passé.
    private static func countsForInstalledVersion(
        of mod: ModItem, in history: ModErrorHistory
    ) -> (errors: Int, warnings: Int) {
        guard let record = history.history(for: mod.folderName)
            .first(where: { $0.version == mod.version })
        else { return (0, 0) }
        return (record.errorCount, record.warningCount)
    }
}
