import Foundation

/// Le cadrage courant de la liste des mods : ce qu'on cherche, ce qu'on filtre,
/// comment on trie, où on en est dans la pagination.
///
/// Porté par le ViewModel plutôt que par des `@State` de `ModListView` : SwiftUI
/// détruit l'état local d'une vue quand elle quitte l'écran, si bien qu'un
/// aller-retour vers l'onglet Diagnostic remettait la liste à zéro — tri,
/// filtres et page compris.
///
/// La remise à la page 1 est portée par le type et non par la vue. Elle y vivait
/// sous la forme de cinq `.onChange` séparés, un par critère : ajouter un
/// sixième filtre sans son `.onChange` laissait l'utilisateur sur une page qui
/// n'existe plus dans le résultat filtré, c'est-à-dire devant une liste vide.
/// Ici l'oubli n'est plus possible.
///
/// Pas dans `StarHubTHCore`, donc pas de test unitaire : `CategoryScope` dépend
/// de `NexusCategory`, qui porte des `Color` SwiftUI.
struct ModListFilters: Equatable {
    var search: String = "" {
        didSet { if search != oldValue { page = 1 } }
    }
    var scope: ModFilter = .all {
        didSet { if scope != oldValue { page = 1 } }
    }
    var category: CategoryScope = .all {
        didSet { if category != oldValue { page = 1 } }
    }
    var configOnly: Bool = false {
        didSet { if configOnly != oldValue { page = 1 } }
    }
    var frenchTranslation: FrenchTranslationScope = .off {
        didSet { if frenchTranslation != oldValue { page = 1 } }
    }
    /// Le tri ne remet **pas** à la page 1 : réordonner ne change pas le nombre
    /// de résultats, et repartir du début ferait perdre sa place à qui compare
    /// deux tris sur une liste de plusieurs centaines de mods.
    var sort: ModSortOrder = .name

    /// Page courante (1-based).
    var page: Int = 1

    /// Ramène la liste à un état où un mod donné est forcément visible : tout
    /// filtre susceptible de l'écarter est levé. Utilisé par le saut vers un
    /// mod (ligne de journal, carte de diagnostic, recherche guidée).
    mutating func focus(on searchTerm: String) {
        scope = .all
        category = .all
        configOnly = false
        frenchTranslation = .off
        search = searchTerm
        page = 1
    }
}
