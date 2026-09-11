import Foundation

/// Le parcours d'une archive dépliée, dans son propre fichier : l'ajouter à
/// `ManifestlessArchive.swift` faisait franchir à celui-ci le seuil de
/// `oversized_files`.
extension ManifestlessArchive {
    /// Les chemins d'une archive dépliée, relatifs à sa racine — l'entrée de
    /// `classify(paths:installedFolderNames:)`.
    ///
    /// Fichiers réguliers seulement (un dossier n'est pas une entrée de dépôt)
    /// et rien de caché : `.DS_Store` et `__MACOSX` voyagent dans presque
    /// toutes les archives faites sur macOS, et les déposer dans le mod de
    /// l'utilisateur serait faux deux fois — posés, puis inscrits au registre
    /// comme des fichiers à retirer.
    ///
    /// ⚠️ **Les chemins se comparent résolus, des deux côtés.** `enumerator`
    /// rend des URLs dont les liens symboliques sont suivis (`/var/…` →
    /// `/private/var/…` sur macOS) alors que la racine passée peut ne pas
    /// l'être. Sans cette résolution, le préfixe ne correspond jamais et la
    /// liste sort **vide** : une archive parfaitement valide devient « contenu
    /// non reconnu », sans erreur ni journal.
    public static func paths(under root: URL,
                             fileManager: FileManager = .default) -> [String] {
        guard let walker = fileManager.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        else { return [] }
        var paths: [String] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let full = url.resolvingSymlinksInPath().path
            let base = root.resolvingSymlinksInPath().path + "/"
            if full.hasPrefix(base) { paths.append(String(full.dropFirst(base.count))) }
        }
        return paths
    }
}
