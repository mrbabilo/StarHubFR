import Foundation
import Combine

/// Porteur observable du cadrage de la liste, **séparé du ViewModel**.
///
/// Ce n'est pas un détail d'organisation : un `@Published` sur le ViewModel
/// publie à toute la fenêtre, `MainView` comprise — barre latérale, en-tête,
/// zone de contenu. Chaque lettre tapée dans le champ de recherche redessinait
/// donc l'application entière, et la frappe accusait une latence perceptible
/// à ~900 mods. Un objet observable à part limite la publication à qui
/// l'observe, c'est-à-dire `ModListView` seule — la portée qu'avaient les
/// `@State` d'origine, sans leur défaut (ils mouraient avec la vue).
///
/// Même motif que `vm.bisection`, pour la même raison.
final class ModListState: ObservableObject {
    @Published var filters = ModListFilters()
}

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
        // Pas redondant avec le `didSet` de `search` : sauter deux fois vers le
        // même mod laisse `search` inchangé, donc son `didSet` ne se déclenche
        // pas — et sans cette ligne on resterait sur une page où il n'est pas.
        page = 1
    }
}
