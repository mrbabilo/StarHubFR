import Foundation

/// D'où l'on arrive sur la fiche d'un mod (audit UX 2026-10-16, N-03).
public enum DetailDoor: Equatable, Sendable {
    case listRow, palette, installReport
    /// Une ligne d'Alertes système ; `dependency` quand la cause est une
    /// dépendance manquante ou en pause.
    case alert(dependency: Bool)
    /// Le bandeau d'état de la fiche elle-même.
    case anomalyBanner(dependencyOnly: Bool)
    case affirmedUpdate, nexusUpdate, unverifiable, frenchTranslations, saveFootprint
    case compatibilityCard, performance, extensionSettings
    /// « Ouvrir ce mod » depuis la Santé, le journal ou la bissection (N-02).
    case logJump
}

/// **La règle d'arrivée, une seule** : une porte qui désigne un *problème du
/// mod* ouvre l'onglet qui porte le geste qui le règle ; une porte qui
/// désigne *le mod* ouvre l'Aperçu.
///
/// Avant, chaque appelant écrivait son onglet en dur : la palette et le bilan
/// d'installation ouvraient Santé (le bilan annonce pourtant un delta, montré
/// dans l'Aperçu), et une alerte de dépendance ouvrait Santé alors que
/// « Activer » vit dans Dépendances. Le `switch` est exhaustif, **sans
/// `default:`** : une porte nouvelle doit dire où elle mène.
public enum DetailArrival {
    public static func tab(for door: DetailDoor) -> DetailTab {
        switch door {
        case .listRow, .palette, .installReport, .saveFootprint, .extensionSettings:
            return .overview
        case .alert(let dependency):
            return dependency ? .dependencies : .health
        case .anomalyBanner(let dependencyOnly):
            return dependencyOnly ? .dependencies : .health
        case .affirmedUpdate, .nexusUpdate:
            return .history
        case .unverifiable:
            return .management
        case .frenchTranslations:
            return .translation
        case .compatibilityCard, .performance, .logJump:
            return .health
        }
    }
}
