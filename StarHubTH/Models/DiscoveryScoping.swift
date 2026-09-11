import Foundation

/// Ce que la vitrine montre, et ce qu'elle écarte.
///
/// Trois écarts en une seule passe, plus la reconnaissance d'un mod déjà au
/// parc. Aucun n'était vérifiable dans le ViewModel, et chacun décide de ce que
/// l'utilisateur voit sur un catalogue de plus de 33 000 entrées.
enum DiscoveryScoping {

    /// Une carte de la vitrine : le résultat Nexus, et s'il est déjà au parc.
    struct Row: Identifiable, Equatable, Sendable {
        let hit: NexusModSearch.Hit
        let installed: Bool
        var id: Int { hit.modId }
    }

    /// - Parameters:
    ///   - installedNexusIds: ce que le parc déclare. Reconnaît un mod même
    ///     renommé.
    ///   - installedTitles: les noms du parc. Sur un compte gratuit tout
    ///     s'installe à la main, donc sans identifiant : le titre est alors le
    ///     seul recours.
    ///   - francophoneOnly: vrai pour les sections de la vitrine, **faux pour
    ///     la recherche** — on y cherche un mod précis, et filtrer sur la
    ///     langue ferait conclure « ce mod n'existe pas ».
    ///   - hidingInstalled: retire les installés de la liste. Le badge est
    ///     calculé dans tous les cas : sans lui, un mod déjà posé paraîtrait
    ///     absent de Nexus.
    static func rows(from hits: [NexusModSearch.Hit],
                     installedNexusIds: Set<Int>,
                     installedTitles: Set<String>,
                     hidingInstalled: Bool,
                     francophoneOnly: Bool) -> [Row] {
        hits
            // Contenu adulte (spec §8) et traductions non françaises en
            // vitrine : deux écarts avant même de regarder le parc.
            .filter { !$0.adultContent
                && (!francophoneOnly || NexusModSearch.vitrineEligible($0)) }
            .map { hit in
                let installed = installedNexusIds.contains(hit.modId)
                    || installedTitles.contains { NexusModSearch.namesMatch($0, hit.name) }
                return Row(hit: hit, installed: installed)
            }
            .filter { !(hidingInstalled && $0.installed) }
    }

    /// Reste-t-il une tranche à demander ?
    static func hasMore(received: Int, serverTotal: Int) -> Bool {
        received < serverTotal
    }

    /// L'offset de la tranche suivante : le nombre de résultats **reçus**.
    ///
    /// ⚠️ Jamais le nombre de cartes affichées. Compter les visibles ferait
    /// redemander sans fin ce que les filtres viennent d'écarter — la page
    /// suivante repartirait du même offset, et « voir plus » tournerait en rond.
    static func nextOffset(received: Int) -> Int { received }
}
