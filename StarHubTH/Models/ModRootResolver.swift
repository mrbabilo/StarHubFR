import Foundation

/// Le dossier **réel** d'un mod dont on ne connaît que le nom logique.
///
/// Un mod en pause vit dans un dossier préfixé d'un point (`Mods/.X`), et
/// `ModItem.folderName` n'en porte jamais : composer le chemin à la main manque
/// donc un mod sur deux. **721 des dossiers du parc de référence sont en
/// pause** (mesuré le 2026-09-11).
///
/// ⚠️ **Le point vit sur l'entrée de tête.** Mettre un pack en pause renomme
/// `Mods/Pack`, pas ses composants — la même mesure ne trouve qu'**un seul**
/// dossier pointé au niveau 2 sur tout le parc, et ce n'est pas un mod
/// (`.ModCollectionAlbum/.config`). Chaque niveau est néanmoins essayé, rien
/// n'empêchant un dossier posé à la main.
///
/// 🚩 **Trois autres résolutions coexistent dans le dépôt, et elles divergent**
/// — relevé du 2026-09-11, sans cas réel à l'appui, donc **non unifiées** :
/// `ModConfigBackupManager` et `ModInstallBackupManager.restoreBackup` ne
/// préfixent que la **tête** (ils ne trouveraient pas `Pack/.Composant`), et le
/// second garde exprès les deux chemins pour détecter leur coexistence. Les
/// aligner demanderait de toucher trois chemins d'écriture pour corriger un
/// défaut que le parc ne porte pas.
enum ModRootResolver {

    /// - Returns: le chemin du dossier réel, ou `nil` si l'un des composants
    ///   manque. **`nil` dit « ce mod n'est pas là »** : rendre un chemin
    ///   plausible ferait écrire à côté — dans un dossier inexistant, ou pire,
    ///   dans un autre mod.
    static func physicalRoot(of folderName: String, modsRoot: String,
                             fileManager: FileManager = .default) -> String? {
        var current = modsRoot
        for component in folderName.components(separatedBy: "/") {
            let plain = (current as NSString).appendingPathComponent(component)
            let dotted = (current as NSString).appendingPathComponent("." + component)
            // L'actif d'abord : quand les deux existent — cas réel du parc —
            // c'est celui-là que SMAPI lit.
            if fileManager.fileExists(atPath: plain) { current = plain }
            else if fileManager.fileExists(atPath: dotted) { current = dotted }
            else { return nil }
        }
        return current
    }
}
