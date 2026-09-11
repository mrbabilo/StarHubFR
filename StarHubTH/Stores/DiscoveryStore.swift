import Foundation
import Observation

/// L'état de la vitrine « Découvrir » (axe G) : ce que les trois sections ont
/// rendu, une recherche par nom, la fiche ouverte, la catégorie choisie, et
/// la dernière panne réseau.
///
/// **Ce que l'extraction achète ici est un compteur qui cesse d'exister en
/// double.** Le voyant de chargement ne s'éteint qu'au retour de la
/// *dernière* réponse, pas de la première — la paire compteur/drapeau était
/// écrite deux fois verbatim dans le ViewModel, la forme exacte des
/// divergences que ce dépôt a déjà payées ailleurs.
///
/// Ce qu'il ne fait pas : le réseau (`NexusSearchClient`), le cache disque
/// (`ModCatalog`), ni le calcul des cartes — `discoveryRows` lit `mods` et
/// les identifiants Nexus installés, donc le domaine Scan, extrait en
/// dernier. Le ViewModel garde cette orchestration et mute ce store.
@Observable
final class DiscoveryStore {

    /// L'état de chaque section, tel que le cache ou le réseau l'a rendu.
    private(set) var sections: [ModCatalog.SectionKind: ModCatalog.SectionState] = [:]
    /// Vrai tant qu'une requête de section est en vol.
    private(set) var loading = false
    private(set) var search: DiscoverySearchResult?
    private(set) var detail: NexusModSearch.Detail?
    private(set) var detailState: DiscoveryDetailState = .idle
    /// La dernière panne réseau des sections — un seul message en haut de
    /// l'onglet, chaque section n'a pas à répéter (spec §8).
    private(set) var lastError: NexusSearchError?
    /// La catégorie à laquelle les trois sections sont restreintes, `nil`
    /// pour toutes. Le filtre part au **serveur** : sur 50 mods de tendances
    /// on compte déjà 15 catégories, trier la page reçue n'aurait rien rendu.
    private(set) var category: NexusCategory?

    @ObservationIgnored private var pendingFetches = 0

    // MARK: - Les requêtes en vol

    func beginFetch() {
        pendingFetches += 1
        loading = true
    }

    /// Une réponse est revenue. Le voyant ne s'éteint qu'à la dernière.
    ///
    /// Le plancher à zéro n'est pas décoratif : un rappel en trop ferait
    /// passer le compteur sous zéro, et le voyant resterait alors allumé au
    /// chargement suivant, une requête durant.
    func finishFetch() {
        pendingFetches = max(0, pendingFetches - 1)
        if pendingFetches == 0 { loading = false }
    }

    // MARK: - La catégorie, et les réponses qu'elle périme

    /// Change la catégorie. Rend `false` si c'était déjà celle-là — sans
    /// cette garde, rouvrir le même filtre relancerait trois requêtes pour
    /// rien.
    func setCategory(_ newCategory: NexusCategory?) -> Bool {
        guard newCategory?.id != category?.id else { return false }
        category = newCategory
        return true
    }

    /// Cette réponse concerne-t-elle encore ce qu'on affiche ? Une réponse
    /// peut revenir après que l'utilisateur a changé de catégorie : elle est
    /// alors rangée dans **son** cache, mais pas affichée — sinon la vitrine
    /// montrerait des mods d'une catégorie qu'on vient de quitter.
    ///
    /// « Toutes catégories » (`nil`) est une identité comme une autre, pas un
    /// joker : une réponse « toutes » n'a rien à faire dans une vue filtrée.
    func isStillWanted(category asked: NexusCategory?) -> Bool {
        asked?.id == category?.id
    }

    // MARK: - Publication

    func setSection(_ kind: ModCatalog.SectionKind, to state: ModCatalog.SectionState) {
        sections[kind] = state
    }

    /// Un chargement commence : la panne d'avant ne parle pas de la tentative
    /// qui commence. Sans cette remise à zéro, un bandeau d'erreur restait en
    /// haut de l'onglet pour toujours, y compris après un chargement réussi.
    func startLoad() {
        clearFailure()
    }

    /// Une requête a abouti : le bandeau de la panne précédente n'a plus lieu
    /// d'être. Même effet que `startLoad()`, dit à l'endroit où il se produit
    /// — un succès n'est pas un début de chargement.
    func clearFailure() {
        lastError = nil
    }

    func recordFailure(_ error: NexusSearchError) {
        lastError = error
    }

    func setSearch(_ result: DiscoverySearchResult?) {
        search = result
    }

    func setDetail(_ newDetail: NexusModSearch.Detail?, state: DiscoveryDetailState) {
        detail = newDetail
        detailState = state
    }
}
