import Foundation

/// Un problème de santé du parc, quelle que soit sa source.
///
/// L'écran d'alertes agrégeait trois sections hétérogènes sans dire par quoi
/// commencer. Ce type porte la gravité, seul critère qui permette de trier.
public struct HealthIssue: Identifiable, Equatable {

    /// `Int` brut croissant : le `Comparable` synthétisé donne alors
    /// « critique > avertissement > information », l'ordre du tri.
    public enum Severity: Int, Comparable, CaseIterable {
        case info = 0, warning = 1, critical = 2
        public static func < (a: Severity, b: Severity) -> Bool {
            a.rawValue < b.rawValue
        }

        /// La clé de libellé vit sur le type, pas dans chaque vue : deux
        /// tables de correspondance finiraient par diverger, et une gravité
        /// s'afficherait sous deux noms selon l'écran.
        public var l10nKey: String {
            switch self {
            case .critical: return L10n.Health.severityCritical
            case .warning: return L10n.Health.severityWarning
            case .info: return L10n.Health.severityInfo
            }
        }
    }

    public enum Source: String, Equatable { case smapi, keybind, modConflict }

    /// Une cible, pas seulement un onglet — c'est tout le manque de l'ancien
    /// `openTab(String)` (H-T6b) : « Voir les journaux » ouvrait la vue
    /// générale, « Voir les mods » la liste entière, jamais l'erreur ni le
    /// mod fautif eux-mêmes.
    public enum Action: Equatable {
        /// Ouvre la fiche du mod visé. `query` est ce qu'attend
        /// `ModFocusResolver.resolve(_:in:)` : un nom de dossier pour un
        /// conflit (`ModConflictPair` n'indexe que des `folderName`), un nom
        /// affiché pour une erreur SMAPI ou une collision de raccourcis (ces
        /// deux sources ne connaissent le mod que par le nom sous lequel il
        /// a été chargé).
        case openMod(query: String)
        /// Ouvre les journaux, recherche pré-remplie sur `searchText` — pour
        /// les lignes qui ne désignent aucun mod résolvable (un outil externe
        /// comme RivaTuner, une notice bénigne sans mod nommé) : la fiche
        /// n'existerait pas, le journal reste la seule trace exploitable.
        case openLogs(searchText: String)
    }

    /// Dérivé du **contenu**. Les modèles sources (`SmapiDiagnostics.Issue`,
    /// `MissingDep`, `BenignNotice`) portent un `id = UUID()` régénéré à
    /// chaque construction : l'utiliser ferait sauter les lignes à chaque
    /// relecture du journal.
    public let id: String
    public let severity: Severity
    public let source: Source
    public let title: String
    public let detail: String?
    public let action: Action?

    public init(id: String, severity: Severity, source: Source,
                title: String, detail: String?, action: Action?) {
        self.id = id
        self.severity = severity
        self.source = source
        self.title = title
        self.detail = detail
        self.action = action
    }
}

public extension Array where Element == HealthIssue {
    /// Combien de lignes réclament un GESTE de la part du joueur — ni plus ni
    /// moins que `.critical` + `.warning`. Une notice `.info` reste dans la
    /// liste (l'écran d'alertes l'affiche toujours) mais ne compte pas ici :
    /// `SmapiLogDiagnostics.problemCount` exclut déjà ces mêmes notices
    /// « bénignes » pour la raison exacte que ce compte sert — mesuré sur le
    /// journal réel de l'auteur, 7 notices bénignes et 0 échec/conflit
    /// faisaient sonner la pastille sur un parc sain. La pastille de la barre
    /// latérale ET le pied de `SystemAlertsView` lisent CE compte, jamais
    /// `.count` brut, pour ne jamais diverger.
    var actionableCount: Int {
        filter { $0.severity != .info }.count
    }
}
