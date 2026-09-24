import Foundation

/// Chercher les traductions françaises d'un mod sur Nexus — **le seul chemin**,
/// partagé par le bouton de la fiche (A3-T3) et la page « Traductions FR »
/// (C5-T1). Il vivait en privé dans le ViewModel ; une seconde copie pour la
/// page aurait divergé à la première retouche.
///
/// Deux sources réunies (`FrenchTranslationSweep.merge`) :
/// 1. le **lien** « requis par », quand le mod déclare sa fiche Nexus ;
/// 2. la **recherche par nom** : tag `French` d'abord, puis, si le tag ne rend
///    rien, recherche large lue au titre (trois traductions sur quatre-vingts
///    n'ont pas le tag).
///
/// Le réseau seulement : les requêtes, la lecture et le tri vivent en Core
/// (`NexusModSearch`, `NexusTranslationLinks`, testés).
enum FrenchTranslationLookup {
    typealias SearchError = NexusSearchError

    /// Les deux sources, pour un mod. Échoue si **une** source échoue : un
    /// résultat partiel présenté comme complet dirait « rien d'autre » à tort.
    static func find(name: String, hostModId: Int?) async -> Result<FrenchTranslationSweep.Entry, SearchError> {
        var linked: [NexusModSearch.Hit] = []
        if let hostModId {
            switch await self.linked(hostModId: hostModId) {
            case .success(let hits): linked = hits
            case .failure(let error): return .failure(error)
            }
        }
        switch await byName(name, hostModId: hostModId) {
        case .success(let hits):
            return .success(FrenchTranslationSweep.merge(linked: linked, byName: hits, at: Date()))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Recherche par nom — la séquence d'A3-T3, inchangée.
    static func byName(_ name: String, hostModId: Int?) async -> Result<[NexusModSearch.Hit], SearchError> {
        switch await search(name: name, tag: NexusModSearch.frenchTag) {
        case .failure(let error):
            return .failure(error)
        case .success(let page) where !page.hits.isEmpty:
            // **Le titre classe, il ne filtre pas** : le serveur a déjà trié
            // sur le tag.
            return .success(NexusModSearch.ranked(page.hits, excluding: hostModId))
        case .success:
            // Le filet : recherche large, où seul le titre distingue une
            // traduction — le filtre est à sa place.
            return await search(name: name, tag: nil).map {
                NexusModSearch.frenchTranslations(among: $0.hits, excluding: hostModId)
            }
        }
    }

    /// Les traductions françaises liées à un mod : les tranches de ses
    /// requérants, chacune relue en un appel, jusqu'à `requiringScanLimit`.
    static func linked(hostModId: Int) async -> Result<[NexusModSearch.Hit], SearchError> {
        var offset = 0
        var found: [NexusModSearch.Hit] = []
        while offset < NexusModSearch.requiringScanLimit {
            let page: NexusModSearch.RequiringPage
            switch await requiring(modId: hostModId, offset: offset) {
            case .success(let value): page = value
            case .failure(let error): return .failure(error)
            }
            if !page.modIds.isEmpty {
                switch await mods(ids: page.modIds) {
                case .success(let details): found += details.hits
                case .failure(let error): return .failure(error)
                }
            }
            offset += NexusModSearch.requiringPageSize
            if page.modIds.isEmpty || offset >= page.totalCount { break }
        }
        return .success(NexusModSearch.linkedFrenchTranslations(found, hostModId: hostModId))
    }

    // MARK: - Ponts async

    private static func search(name: String, tag: String?) async -> Result<NexusModSearch.Page, SearchError> {
        await withCheckedContinuation { continuation in
            NexusSearchClient.search(name: name, tag: tag) { continuation.resume(returning: $0) }
        }
    }

    private static func requiring(modId: Int, offset: Int) async -> Result<NexusModSearch.RequiringPage, SearchError> {
        await withCheckedContinuation { continuation in
            NexusSearchClient.requiring(modId: modId, offset: offset) { continuation.resume(returning: $0) }
        }
    }

    private static func mods(ids: [Int]) async -> Result<NexusModSearch.Page, SearchError> {
        await withCheckedContinuation { continuation in
            NexusSearchClient.mods(ids: ids) { continuation.resume(returning: $0) }
        }
    }
}
