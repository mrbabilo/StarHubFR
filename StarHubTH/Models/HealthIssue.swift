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

    public enum Action: Equatable { case openTab(String) }

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
