import Foundation

/// Retrouve le mod qu'une demande de mise au point désigne — « ouvre-moi la
/// fiche de celui-ci » —, d'où qu'elle vienne.
///
/// Les deux origines ne nomment pas les mods de la même façon : la recherche
/// guidée tient un **nom de dossier** de premier niveau (c'est sa clé de
/// travail), le journal de SMAPI un **nom affiché**, qui est celui du composant
/// et pas du pack qui le contient. Un résolveur unique évite que chaque
/// appelant réinvente le sien — il en existait deux, divergents, et aucun ne
/// savait reconnaître un dossier.
public enum ModFocusResolver {
    /// Le mod visé, ou `nil` si rien ne correspond.
    ///
    /// - Parameter mods: les mods de **premier niveau** ; les enfants des packs
    ///   sont parcourus par la fonction elle-même.
    ///
    /// Du plus sûr au plus permissif : dossier exact, puis nom exact, puis
    /// correspondance partielle sur le nom. L'ordre compte — « Content Patcher »
    /// ne doit pas ouvrir « Content Patcher Animations » au prétexte que
    /// celui-ci vient en premier dans la liste.
    public static func resolve(_ query: String, in mods: [ModItem]) -> ModItem? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // `contains("")` est vrai partout : sans cette garde, une demande vide
        // ouvre la fiche du premier mod venu.
        guard !needle.isEmpty else { return nil }

        // Le dossier d'abord, et sur la liste de premier niveau : un pack n'a
        // pas d'existence parmi les enfants, et c'est justement lui que la
        // recherche guidée met en pause.
        if let byFolder = mods.first(where: { $0.folderName == needle }) {
            return byFolder
        }

        let all = mods.flattenedMods + mods
        return all.first { $0.name == needle }
            ?? all.first { $0.name.localizedCaseInsensitiveContains(needle) }
    }
}
