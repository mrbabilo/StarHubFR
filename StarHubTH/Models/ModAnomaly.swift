import Foundation

/// Ce qui empêche un mod de bien tourner, résumé pour sa ligne de liste.
///
/// Cinq signaux, réunis parce qu'ils répondent à la même question — « lequel de
/// ces 863 mods dois-je regarder » — et qu'une seule pastille vaut mieux que
/// cinq qui se disputent la place.
///
/// **L'état actif ne filtre rien, il gradue.** Un mod cassé mis en pause n'est
/// pas un incident du jour, mais il reste à traiter : c'est un dossier à
/// remplacer ou à supprimer. Le masquer parce qu'il dort ferait disparaître les
/// sept mods que smapi.io signale sur ce parc — les sept sont en pause.
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
    /// Le mod est installé plusieurs fois.
    public let duplicate: Duplicate?
    /// Ce que smapi.io dit de sa compatibilité, quand il le signale.
    public let compatibility: ModCompatibility.Status?

    /// Le même mod dans plusieurs dossiers.
    public enum Duplicate: Equatable {
        /// **Au moins deux copies actives** : SMAPI en charge une et laisse
        /// l'autre de côté, sans qu'on puisse prévoir laquelle.
        case active(folders: [String])
        /// Plusieurs copies, une active au plus. Rien ne casse aujourd'hui.
        case dormant(folders: [String])

        /// Les dossiers qui portent ce mod, nommés — c'est ce qui dit lequel
        /// supprimer, là où un simple compte laisse chercher.
        public var folders: [String] {
            switch self {
            case .active(let f), .dormant(let f): return f
            }
        }

        public var copies: Int { folders.count }

        public var isActive: Bool { if case .active = self { return true }; return false }
        public var isDormant: Bool { !isActive }
    }

    public init(severity: Severity, errorCount: Int, warningCount: Int,
                hasDependencyIssue: Bool, isUnloadable: Bool,
                duplicate: Duplicate? = nil,
                compatibility: ModCompatibility.Status? = nil) {
        self.severity = severity
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.hasDependencyIssue = hasDependencyIssue
        self.isUnloadable = isUnloadable
        self.duplicate = duplicate
        self.compatibility = compatibility
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
    ///   - duplicates: l'index des mods installés plusieurs fois, construit une
    ///     fois par scan — cette fonction tourne sur chaque ligne du parc.
    ///   - compatibility: le verdict de smapi.io par `UniqueID`. Absent ne veut
    ///     pas dire sain : deux tiers du parc lui sont inconnus.
    public static func anomaly(for mod: ModItem,
                               history: ModErrorHistory,
                               dependencyIssue: (ModItem) -> Bool,
                               duplicates: ModDuplicateIndex = .empty,
                               compatibility: [String: ModCompatibility.Status] = [:])
        -> ModAnomaly? {
        // Un en-tête de pack porte l'anomalie de ses composants : sans ça, il
        // faudrait déplier chaque pack pour découvrir lequel pose problème. Les
        // composants gardent la leur — contrairement au poids, une erreur
        // s'attribue à un composant précis, elle ne se compte pas deux fois.
        let subjects = [mod] + (mod.children ?? [])

        var errors = 0
        var warnings = 0
        var dependency = false
        var unloadable = false
        var duplicate: ModAnomaly.Duplicate?
        var compatStatus: ModCompatibility.Status?
        var compatOnActiveMod = false

        for subject in subjects {
            let counts = countsForInstalledVersion(of: subject, in: history)
            errors += counts.errors
            warnings += counts.warnings
            if dependencyIssue(subject) { dependency = true }
            // Un en-tête de pack n'a **jamais** d'`UniqueID` : c'est sa nature,
            // pas une anomalie. Le tester le signalerait tous.
            if !subject.isGroup, subject.uniqueId.isEmpty { unloadable = true }

            // Le pire des composants l'emporte : c'est le dossier de premier
            // niveau qu'on regarde, et il faut qu'il dise le plus grave. Un
            // doublon actif chasse un dormant, jamais l'inverse — et deux
            // dormants ne se remplacent pas l'un l'autre, sans quoi les
            // dossiers nommés dépendraient de l'ordre des composants.
            if let found = duplicates.duplicate(of: subject.uniqueId),
               duplicate == nil || (found.isActive && duplicate?.isDormant == true) {
                duplicate = found
            }
            if let status = compatibility[subject.uniqueId], status.needsAttention {
                if compatStatus == nil || status.severity > (compatStatus?.severity ?? 0) {
                    compatStatus = status
                }
                // **Indépendant du statut retenu.** Un pack dont un composant
                // cassé est actif et un autre en pause doit compter comme
                // actif, quel que soit celui dont le verdict l'emporte.
                if subject.isEnabled { compatOnActiveMod = true }
            }
        }

        // Ce qui casse **aujourd'hui** : le mod ne tourne pas, ou deux copies
        // actives se disputent la place, ou un mod cassé est activé.
        let breaksNow = errors > 0 || dependency || unloadable
            || duplicate?.isActive == true
            || (compatStatus != nil && compatOnActiveMod)
        if breaksNow {
            return ModAnomaly(severity: .error, errorCount: errors, warningCount: warnings,
                              hasDependencyIssue: dependency, isUnloadable: unloadable,
                              duplicate: duplicate, compatibility: compatStatus)
        }
        // Ce qui reste à traiter sans rien casser : un doublon dormant, un mod
        // cassé qu'on a mis en pause, les avertissements du journal.
        if warnings > 0 || duplicate != nil || compatStatus != nil {
            return ModAnomaly(severity: .warning, errorCount: 0, warningCount: warnings,
                              hasDependencyIssue: false, isUnloadable: false,
                              duplicate: duplicate, compatibility: compatStatus)
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
