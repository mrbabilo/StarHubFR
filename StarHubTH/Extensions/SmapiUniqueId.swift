import Foundation

/// Helpers pour parser un `UniqueID` SMAPI au format `<Author>.<ModName>`.
/// Utilisés pour construire des termes de recherche Nexus lisibles depuis les
/// identifiants techniques présents dans les `manifest.json`.
extension String {
    /// Nom de mod lisible dérivé de l'uniqueId : le dernier segment après le
    /// point, avec le camelCase séparé en mots.
    /// `Pathoschild.ContentPatcher` → `Content Patcher`,
    /// `Parrot.RomRas` → `Rom Ras`.
    var smapiModName: String {
        let last = split(separator: ".").last.map(String.init) ?? self
        return last.smapiSplitCamelCase()
    }

    /// Nom de l'auteur dérivé de l'uniqueId : le premier segment avant le
    /// point. Chaîne vide si l'uniqueId ne contient pas de point (pas d'auteur
    /// distinct du nom).
    /// `Parrot.RomRas` → `Parrot`, `ContentPatcher` → ``.
    var smapiAuthor: String {
        let segments = split(separator: ".").map(String.init)
        guard segments.count >= 2, let author = segments.first, !author.isEmpty else {
            return ""
        }
        return author
    }

    /// Sépare le camelCase en mots : `ContentPatcher` → `Content Patcher`.
    fileprivate func smapiSplitCamelCase() -> String {
        reduce(into: "") { result, char in
            if char.isUppercase && !result.isEmpty {
                result.append(" ")
            }
            result.append(char)
        }
    }
}
