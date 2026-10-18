import Foundation

/// N-04 — ce que l'Accueil ajoute sous ses tuiles (décision de l'auteur du
/// 2026-10-18 : bandeau et tuiles gardés). Les tuiles comptent ; ces deux
/// sections **nomment** : chaque ligne désigne un mod ou un problème et mène
/// à l'endroit où il se règle.
public enum HomeAgenda {
    /// Au-delà, la section deviendrait une seconde page d'alertes.
    public static let limit = 5

    public struct ToFix: Equatable {
        public let rows: [HealthIssue]
        /// Ce qui ne tient pas dans les cinq lignes : « Voir les N autres ».
        public let remaining: Int
    }

    /// « À régler » : les problèmes des Alertes système qui réclament un geste
    /// (`.info` écarté, comme la pastille), critiques d'abord, l'ordre des
    /// Alertes gardé dans chaque gravité.
    public static func toFix(_ issues: [HealthIssue]) -> ToFix {
        let actionable = issues.enumerated()
            .filter { $0.element.severity != .info }
            // `sorted` n'est pas stable en Swift : départage par la position.
            .sorted { a, b in
                a.element.severity != b.element.severity
                    ? a.element.severity > b.element.severity
                    : a.offset < b.offset
            }
            .map(\.element)
        return ToFix(rows: Array(actionable.prefix(limit)),
                     remaining: max(0, actionable.count - limit))
    }

    /// Où mène un clic sur la ligne : le premier chemin qui **ouvre** quelque
    /// chose. Renommer, réparer, réinstaller ou montrer dans le Finder restent
    /// aux Alertes système, où leur feuille et leurs gardes vivent : `nil`,
    /// et la ligne y conduit.
    public static func destination(of issue: HealthIssue) -> HealthIssue.Action? {
        issue.actions.first { action in
            switch action {
            case .openMod, .openModDependencies, .openModConfig, .openLogs: return true
            case .revealInFinder, .renameFolder, .repairManifest, .reinstallFromNexus: return false
            }
        }
    }

    /// « Récemment installés » : les mods de premier niveau (un pack compte
    /// pour une ligne, à la date de son composant le plus récent, comme le
    /// tri « Date d'installation » de la liste), le plus récent d'abord. Un
    /// mod sans date connue n'y figure pas.
    public static func recentlyInstalled(_ mods: [ModItem]) -> [ModItem] {
        let dated = mods.compactMap { mod in mod.effectiveInstallDate.map { (mod, $0) } }
        return Array(dated.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0))
    }
}
