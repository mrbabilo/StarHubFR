import Foundation

/// Le dossier **réel** d'un mod à partir de son nom logique : `Mods/X`
/// actif, `Mods/.X` en pause, `Mods/.Tête/Reste` pour un composant d'un pack
/// en pause (le point vit sur l'entrée de tête). `nil` si aucun n'existe —
/// toute écriture saute alors plutôt que fabriquer un dossier sans manifeste.
public enum ModFolderPaths {
    public static func realFolder(modsRoot: URL, logical: String) -> URL? {
        var candidates = [logical, "." + logical]
        let parts = logical.split(separator: "/", maxSplits: 1)
        if parts.count == 2 { candidates.append(".\(parts[0])/\(parts[1])") }
        return candidates.map { modsRoot.appendingPathComponent($0, isDirectory: true) }.first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
}
