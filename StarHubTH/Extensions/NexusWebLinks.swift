import AppKit

/// Ouverture des pages de recherche du **site** Nexus Mods — pas l'API :
/// une dépendance manquante ou un auteur n'a pas de fiche locale, la vue
/// délègue au navigateur. Une seule copie : l'URL est un contrat que
/// `check_sources.py` ne couvre pas (pages web, pas API), et trois vues la
/// portaient chacune en double (passe de simplification 2026-10-03).
enum NexusWebLinks {
    /// Recherche plein texte du site pour un terme donné.
    static func openSearch(for searchTerm: String) {
        let encoded = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchTerm
        if let url = URL(string: "https://www.nexusmods.com/stardewvalley/search/?gsearch=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// La liste des mods d'un auteur. Le filtre `?author=` est plus précis
    /// qu'une recherche plein texte pour retrouver tous les mods d'un même
    /// auteur.
    static func openAuthorSearch(for author: String) {
        let encoded = author.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? author
        if let url = URL(string: "https://www.nexusmods.com/games/stardewvalley/mods?author=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }
}
