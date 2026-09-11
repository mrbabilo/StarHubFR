import Foundation

/// Ce qu'une recherche par nom a rendu, dans la vitrine.
///
/// Vivait imbriqué dans le ViewModel ; déménage en Core avec
/// `DiscoveryStore`, qui le porte.
struct DiscoverySearchResult {
    let rows: [DiscoveryScoping.Row]
    let totalCount: Int
    /// Le terme qui a produit ces lignes — « voir plus » redemande la
    /// tranche suivante du **même** terme, pas de ce que le champ de
    /// recherche contient au moment du clic.
    let term: String
    /// Les résultats reçus, doublons compris — ce sur quoi se calcule la
    /// tranche suivante.
    let loaded: Int

    init(rows: [DiscoveryScoping.Row], totalCount: Int, term: String, loaded: Int) {
        self.rows = rows
        self.totalCount = totalCount
        self.term = term
        self.loaded = loaded
    }
}

/// Où en est une fiche demandée depuis la vitrine.
enum DiscoveryDetailState { case idle, loading, loaded, failed }
