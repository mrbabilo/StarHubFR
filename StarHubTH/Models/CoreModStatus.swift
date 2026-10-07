import Foundation

/// L'état d'un outil externe (`unar`, `7z`) tel que les réglages l'affichent.
/// Les mods de la même section passent par `AppExtension` et `ModPresence`.
enum CoreModStatus {
    case enabledAndInstalled
    case installedButDisabled
    case notInstalled
}
