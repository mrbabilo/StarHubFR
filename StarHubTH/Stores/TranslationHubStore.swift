import Foundation
import Observation

/// L'état du hub de traduction FR : le registre de ce qui est posé, les deux
/// moitiés du dernier résultat de recherche, et les vols mod par mod.
///
/// Le registre (`InstalledTranslationRegistry`) et ses règles sont en Core et
/// testés ; le store les **publie**. Les règles de couplage épinglées ici :
///
/// - une recherche rend **deux moitiés** — les propositions et ce qui est
///   déjà posé. La moitié posée est celle qui dit qu'une version plus
///   récente existe ; la jeter faisait disparaître la pastille de mise à
///   jour. Les vider se fait **ensemble** (`clearSearchResults`).
/// - les vols (`searching`, `busy`) sont des **ensembles**, pas des
///   drapeaux : la fiche désactive ses boutons mod par mod — un verrou
///   unique rendait muet le clic sur un second mod, dont le bouton restait
///   actif sans rien faire.
///
/// Ce qu'il ne fait pas : le réseau, le disque (`InstalledTranslationStore`),
/// ni l'installation (`ManifestlessInstaller`). L'orchestration reste au
/// ViewModel.
@Observable
final class TranslationHubStore {

    /// Ce qui est posé sur quel mod. Reçu des préférences au lancement,
    /// persisté par l'appelant après chaque mutation.
    private(set) var installed = InstalledTranslationRegistry()

    /// Les propositions de la dernière recherche, par mod hôte. Ce n'est pas
    /// un cache : c'est le résultat de la dernière question posée.
    private(set) var hits: [String: [NexusModSearch.Hit]] = [:]
    /// Les résultats **correspondant à ce qui est déjà posé**, retirés des
    /// propositions mais gardés : c'est là que se lit une version plus
    /// récente, et c'est vers eux que rattache le menu.
    private(set) var installedHits: [String: [NexusModSearch.Hit]] = [:]

    /// Les mods dont une recherche de traduction tourne.
    private(set) var searching: Set<String> = []
    /// Les mods dont une traduction s'installe ou se retire.
    private(set) var busy: Set<String> = []

    /// Les fiches Nexus candidates pour un mod sans identifiant, par mod hôte.
    private(set) var identitySearches: [String: IdentitySearch] = [:]
    /// Les mods dont une recherche d'identité tourne.
    private(set) var identitySearching: Set<String> = []

    /// Les suppléments trouvés pour un mod, par mod hôte.
    private(set) var supplementSearches: [String: SupplementSearch] = [:]
    /// Les mods dont une recherche de suppléments tourne.
    private(set) var supplementsSearching: Set<String> = []

    // MARK: - Le registre

    /// Le chargement initial, depuis les préférences.
    func setInstalled(_ newRegistry: InstalledTranslationRegistry) {
        installed = newRegistry
    }

    /// Muté en place, sous observation. La **persistance** reste à l'appelant :
    /// le registre est la seule trace des traductions posées, sa perte rend
    /// toute désinstallation impossible.
    func mutateInstalled(_ change: (inout InstalledTranslationRegistry) -> Void) {
        change(&installed)
    }

    // MARK: - Les résultats

    /// `nil` retire la clé — une valeur vide cachée ferait croire à un
    /// résultat de recherche qui n'existe pas.
    func setHits(_ newHits: [NexusModSearch.Hit]?, for folder: String) {
        if let newHits { hits[folder] = newHits } else { hits[folder] = nil }
    }

    func setInstalledHits(_ newHits: [NexusModSearch.Hit], for folder: String) {
        installedHits[folder] = newHits
    }

    /// Une nouvelle recherche ne doit rien hériter de la précédente — ni des
    /// propositions, ni de la moitié posée.
    func clearSearchResults() {
        hits = [:]
        installedHits = [:]
    }

    // MARK: - Les vols

    func setSearching(_ searching: Bool, for folder: String) {
        if searching { self.searching.insert(folder) } else { self.searching.remove(folder) }
    }

    func isSearching(_ folder: String) -> Bool { searching.contains(folder) }

    func setBusy(_ busy: Bool, for folder: String) {
        if busy { self.busy.insert(folder) } else { self.busy.remove(folder) }
    }

    func isBusy(_ folder: String) -> Bool { busy.contains(folder) }

    // MARK: - L'identité d'un mod sans fiche

    /// `nil` retire la clé — même convention que `setHits` : une valeur vide
    /// cachée ferait croire à un résultat de recherche qui n'existe pas.
    func setIdentitySearch(_ newSearch: IdentitySearch?, for folder: String) {
        identitySearches[folder] = newSearch
    }

    func setIdentitySearching(_ searching: Bool, for folder: String) {
        if searching { identitySearching.insert(folder) } else { identitySearching.remove(folder) }
    }

    func isIdentitySearching(_ folder: String) -> Bool { identitySearching.contains(folder) }

    // MARK: - Les suppléments

    /// `nil` retire la clé — même convention que `setHits`.
    func setSupplementSearch(_ newSearch: SupplementSearch?, for folder: String) {
        supplementSearches[folder] = newSearch
    }

    func setSupplementsSearching(_ searching: Bool, for folder: String) {
        if searching { supplementsSearching.insert(folder) } else { supplementsSearching.remove(folder) }
    }

    func isSupplementsSearching(_ folder: String) -> Bool { supplementsSearching.contains(folder) }
}

/// Ce qu'une recherche d'identité a rendu — voir
/// `NexusModSearch.identityCandidates`.
///
/// `received` et `serverTotal` sont là pour la même raison que dans
/// `SupplementSearch` : la liste est plafonnée par la requête, et taire le
/// total ferait passer une poignée pour une réponse complète.
struct IdentitySearch {
    let candidates: [NexusModSearch.IdentityCandidate]
    let received: Int
    let serverTotal: Int

    var isCapped: Bool { serverTotal > received }
}

/// Ce qu'une recherche de suppléments a rendu.
///
/// - `serverTotal` est ce que Nexus annonce pour ce nom, traductions
///   comprises — 428 pour « Content Patcher ».
///
/// Annoncer `hits.count` seul ferait passer une poignée pour une
/// exhaustivité ; annoncer `serverTotal` seul promettrait des suppléments
/// là où il n'y a que des traductions. Il faut les deux.
struct SupplementSearch {
    let hits: [NexusModSearch.Hit]
    /// Ceux que le parc porte déjà — montrés à part plutôt que proposés.
    let alreadyInstalled: [NexusModSearch.Hit]
    let received: Int
    let serverTotal: Int

    /// `true` quand Nexus en avait plus que la page n'en a rapporté.
    var isCapped: Bool { serverTotal > received }
}
