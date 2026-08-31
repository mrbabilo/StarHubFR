import Foundation

/// Protocole Core pour la résolution de clés L10n.
/// Permet à `SaveFarmNameResolver` (Core) d'être testé sans dépendance au VM.
public protocol L10nResolver: AnyObject {
    func localized(_ key: String) -> String
}