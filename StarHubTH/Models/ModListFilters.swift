import Foundation
import Combine

/// Scope filter for the mods list.
enum ModFilter: String, CaseIterable, Identifiable {
    case all, enabled, disabled, issues
    var id: String { rawValue }
}

/// Three-state French-translation filter: off (all mods), only mods that ship
/// an `fr` i18n file, or only mods that don't. Matches `ModItem.languages`
/// (lowercased codes from the mod's `i18n/` folder).
enum FrenchTranslationScope: Equatable {
    case off
    case available   // ships an i18n/fr.json
    /// Traduit, mais pas entièrement — ceux sur lesquels il reste à faire.
    /// Sur le parc, 31 mods contre 392 complets : sans ce cadrage ils sont
    /// introuvables.
    case partial
    case missing     // translatable, but ships no i18n/fr.json
    /// Traduit, mais l'anglais a bougé depuis — par la date du fichier ou par
    /// une clé dont la référence ne correspond plus. 18 mods du parc au premier
    /// lancement, sans qu'aucun diff ait été ouvert.
    case stale
}

/// Scope for the category-filter menu: show everything, scope to one Nexus
/// category, or scope to mods with no category assigned. A single enum
/// (rather than `NexusCategory?` plus a separate boolean) keeps these three
/// states mutually exclusive by construction.
enum CategoryScope: Equatable {
    case all
    case category(NexusCategory)
    case inferredTag(String)   // stable inferTag key, for mods with no Nexus category
    case uncategorized         // mods with no Nexus category whose inferred tag is "Other"
}

/// Sort order for the mods list. `.name` matches `vm.mods`'s existing
/// alphabetical order (so no extra sort is needed for it); `.activationOrder`
/// sorts by `vm.modActivationTimestamps`, most recent first; `.installDate`
/// sorts by `installedFileDate` (folder mod date), most recent first.
enum ModSortOrder: String, CaseIterable, Identifiable {
    case name, nameDescending, activationOrder, installDate, author, version, size
    var id: String { rawValue }
}

// MARK: -

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

    /// Le cadrage ordonné courant (noms de dossier, premier niveau), tel que
    /// la liste vient de le rendre — liste **et** grille partagent ce flux.
    ///
    /// Volontairement **non publié** : la fiche et la liste s'excluent dans
    /// `MainView`, le cadrage ne peut pas bouger sous une fiche ouverte (et
    /// supprimer un mod ferme sa fiche). La fiche le lit à l'ouverture ; un
    /// `@Published` de plus ici redessinerait pour rien — et sur le
    /// ViewModel, il rouvrirait la régression de frappe que ce type a
    /// fermée (le pager de fiche s'en sert, H-T4b).
    var displayOrder: [String] = []
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
/// Les enums de cadrage ci-dessus vivaient dans `ModListView.swift` : ils
/// remontaient dans `Models/` (F1 — la règle « chaque axe extrait ce qu'il
/// touche ») pour que ce type entre dans `StarHubTHCore` et se teste. Le
/// blocage documenté ici — `CategoryScope` dépend de `NexusCategory`, qui
/// porte des `Color` SwiftUI — est levé en listant `NexusCategory` dans le
/// module : `AppDesignCore` y prouve déjà que SwiftUI y compile.
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
    /// N'afficher que les mods marqués d'une étoile.
    var favoritesOnly: Bool = false {
        didSet { if favoritesOnly != oldValue { page = 1 } }
    }
    /// N'afficher que les mods « à écarter ». Filtre **positif** : par
    /// défaut tout le monde passe, seuls les blacklistés restent quand il
    /// est actif. Le mod grisé se laisse toujours trouver sans ce filtre.
    var blacklistedOnly: Bool = false {
        didSet { if blacklistedOnly != oldValue { page = 1 } }
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
        favoritesOnly = false
        blacklistedOnly = false
        frenchTranslation = .off
        search = searchTerm
        // Pas redondant avec le `didSet` de `search` : sauter deux fois vers le
        // même mod laisse `search` inchangé, donc son `didSet` ne se déclenche
        // pas — et sans cette ligne on resterait sur une page où il n'est pas.
        page = 1
    }
}
