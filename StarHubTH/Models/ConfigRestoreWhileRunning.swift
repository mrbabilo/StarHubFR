import Foundation

/// Restaurer des `config.json` pendant que le jeu tourne : un mod chargé
/// réécrit le sien à son prochain enregistrement (menu de réglages en jeu,
/// GMCM, MLD's Keybind qui enregistre à chaque changement) et défait la
/// restauration sans rien dire. Un mod en pause n'est pas chargé : il ne
/// réécrit rien, et la plupart des configs du parc sont les siennes.
public enum ConfigRestoreWhileRunning {
    /// Les noms affichés des mods restaurés qui sont actifs, dans l'ordre de
    /// la sélection ; vide quand le jeu est fermé.
    public static func activeNames(_ items: [ModConfigBackupItem], mods: [ModItem],
                                   gameRunning: Bool) -> [String] {
        guard gameRunning else { return [] }
        let active = Set(mods.flattenedMods.filter(\.isEnabled).map(\.folderName))
        return items.filter { active.contains($0.modFolderName) }.map(\.modDisplayName)
    }
}
