import Foundation

/// Résout le nom affiché et le tooltip d'une ferme à partir d'un `SaveGameInfo`.
/// Pure Core : prend un `L10nResolver` au lieu du VM directement, pour être
/// testable sans dépendance au god-object.
public enum SaveFarmNameResolver {
    /// Retourne le nom localisé de la ferme (résolu via le resolver).
    /// - whichFarm 0...7 vanilla : clé L10n résolue.
    /// - whichFarm >= 8 ou < 0 (mod farm) : `modFarmName` ou fallback localisé.
    public static func resolve(_ info: SaveGameInfo, resolver: L10nResolver) -> String {
        if info.whichFarm < 0 || info.whichFarm >= 8 {
            return info.modFarmName ?? resolver.localized(L10n.Saves.farmTypeMod)
        }
        return resolver.localized(info.farmTypeName)
    }

    /// Tooltip résolu : "Farm type: <nom>" / "Type de ferme : <nom>".
    public static func heroHelp(for info: SaveGameInfo, resolver: L10nResolver) -> String {
        let displayName = resolve(info, resolver: resolver)
        return String(format: resolver.localized(L10n.Saves.heroFarmHelpFormat),
                      displayName)
    }
}