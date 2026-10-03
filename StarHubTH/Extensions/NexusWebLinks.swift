import AppKit

/// Ouverture des pages de recherche du **site** Nexus Mods — pas l'API :
/// une dépendance manquante ou un auteur n'a pas de fiche locale, la vue
/// délègue au navigateur. Mince wrapper AppKit : les URL elles-mêmes sont
/// construites par `MissingDependencies` (Core, testé), seul domicile —
/// avant la passe de simplification 2026-10-03, trois vues portaient une
/// copie identique et `MissingDependencies` une quatrième.
enum NexusWebLinks {
    /// Recherche plein texte du site pour un terme donné.
    static func openSearch(for searchTerm: String) {
        if let url = MissingDependencies.searchPage(for: searchTerm) {
            NSWorkspace.shared.open(url)
        }
    }

    /// La liste des mods d'un auteur. Le filtre `?author=` est plus précis
    /// qu'une recherche plein texte pour retrouver tous les mods d'un même
    /// auteur.
    static func openAuthorSearch(for author: String) {
        if let url = MissingDependencies.authorPage(for: author) {
            NSWorkspace.shared.open(url)
        }
    }
}
