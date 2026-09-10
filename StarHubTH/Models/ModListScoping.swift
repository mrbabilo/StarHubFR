import Foundation

/// La règle qui décide quels mods la liste montre — et, depuis X57, ceux sur
/// lesquels la bascule en masse agit.
///
/// Elle vivait dans `ModListView`, puis dans le ViewModel : dans les deux cas
/// hors de portée de `swift test`, alors qu'elle commande **ce que
/// l'utilisateur voit**. Extraite le 2026-09-10 (point 2 du §5 de
/// `docs/REFACTORING.md`), par lots : ce fichier ne porte pour l'instant que
/// les prédicats dont les entrées sont **des valeurs** — le mod, les filtres, et
/// au plus un `Set` de noms de dossiers. Ceux qui ont besoin d'un verdict
/// calculé (catégorie, anomalie, couverture française) suivront avec le paquet
/// de closures qu'ils demandent.
///
/// Pourquoi des fonctions statiques et non un type à état : la règle n'a pas de
/// mémoire. Chaque prédicat répond d'un mod et d'un cadrage, sans rien retenir
/// entre deux appels — l'y forcer inviterait à y ranger un cache, et un cache
/// invalidé au mauvais moment est précisément ce qui fait diverger deux
/// pipelines jumeaux (X45 en comptait dix).
enum ModListScoping {

    /// `mod` satisfait-il `predicate`, ou — pour un pack — l'un de ses
    /// composants ?
    ///
    /// L'unique test « cette ligne correspond-elle à X », partagé par la
    /// recherche et le filtre des problèmes, de sorte que les deux ne puissent
    /// pas dériver indépendamment. Les `dependencies`/`uniqueId` propres d'un
    /// en-tête de pack étant vides, l'éprouver lui-même avant ses composants est
    /// toujours sûr, et le plus souvent sans effet.
    static func matchesSelfOrAnyChild(_ mod: ModItem,
                                      _ predicate: (ModItem) -> Bool) -> Bool {
        if predicate(mod) { return true }
        if mod.isGroup, let children = mod.children {
            return children.contains(where: predicate)
        }
        return false
    }

    /// La recherche porte sur le nom **et** l'identifiant : c'est par le second
    /// qu'un mod se retrouve quand son nom affiché ne dit rien à personne.
    static func matchesSearch(_ mod: ModItem, filters: ModListFilters) -> Bool {
        filters.search.isEmpty || matchesSelfOrAnyChild(mod) {
            $0.name.localizedCaseInsensitiveContains(filters.search)
                || $0.uniqueId.localizedCaseInsensitiveContains(filters.search)
        }
    }

    static func matchesConfig(_ mod: ModItem, filters: ModListFilters) -> Bool {
        !filters.configOnly || matchesSelfOrAnyChild(mod) { $0.hasConfigFile }
    }

    /// Le favori se marque sur la ligne de premier niveau, donc se teste sur
    /// elle : un pack est favori pour lui-même, pas par l'un de ses composants.
    ///
    /// - Parameter favorites: les dossiers marqués, tels que le magasin les
    ///   porte. Ils arrivent en valeur — la marque est un `Set` de noms, pas un
    ///   calcul, et la faire entrer par une closure masquerait qu'elle est
    ///   gratuite.
    static func matchesFavorites(_ mod: ModItem, filters: ModListFilters,
                                 favorites: Set<String>) -> Bool {
        !filters.favoritesOnly || favorites.contains(mod.folderName)
    }

    /// Le cadrage « écarter » : laisse passer tout le monde par défaut, ne garde
    /// que les mods écartés quand le filtre est actif. Symétrique de
    /// `matchesFavorites` — voir son commentaire pour le pourquoi du premier
    /// niveau.
    static func matchesBlacklisted(_ mod: ModItem, filters: ModListFilters,
                                   blacklisted: Set<String>) -> Bool {
        !filters.blacklistedOnly || blacklisted.contains(mod.folderName)
    }
}
