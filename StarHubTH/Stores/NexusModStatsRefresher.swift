import Foundation

/// A3-T8 — approbations et dates de mise à jour de tout le parc, par lots
/// sans clé (`NexusModStats`), une fois par jour. Un passage par session au
/// plus tant qu'un lot échoue : sinon chaque ouverture de la liste relancerait
/// ses requêtes. Un lot en échec n'efface rien ; la date du passage n'avance
/// que s'il est complet.
@MainActor
enum NexusModStatsRefresher {
    private static let refreshedAtKey = "nexusStatsRefreshedAt"
    private static var attempted = false

    static func refreshIfDue(viewModel: StarHubTHViewModel, checker: NexusUpdateChecker = .shared) {
        let last = UserDefaults.standard.object(forKey: refreshedAtKey) as? Date
        guard !attempted, NexusModStats.isDue(lastRefresh: last) else { return }
        attempted = true
        let ids = (viewModel.mods + viewModel.mods.flattenedMods)
            .compactMap { Int(viewModel.resolvedNexusModId(for: $0)) }
        Task {
            let (stats, complete) = await fetch(ids)
            guard !stats.isEmpty else { return }
            viewModel.nexusModExtras = checker.mergeCachedExtras { NexusModStats.merge(stats, into: $0) }
            if complete { UserDefaults.standard.set(Date(), forKey: refreshedAtKey) }
            viewModel.log("Nexus : approbations et dates de \(stats.count) mods rafraîchies"
                          + (complete ? "" : " (lot incomplet, nouvel essai à la prochaine session)"))
        }
    }

    /// Les relevés de ces pages, 80 par requête sans clé. `complete` est
    /// faux dès qu'un lot échoue ; ses pages manquent simplement.
    static func fetch(_ ids: [Int]) async -> (stats: [Int: NexusModStats.Entry], complete: Bool) {
        var stats: [Int: NexusModStats.Entry] = [:]
        var complete = true
        for batch in NexusModStats.batches(ids) {
            guard let body = NexusModStats.body(ids: batch),
                  let request = NexusRequestBuilder.makeGraphQLRequest(body: body, apiKey: nil),
                  let answer = try? await URLSession.shared.data(for: request),
                  let part = NexusModStats.decode(answer.0) else { complete = false; continue }
            stats.merge(part) { $1 }
        }
        return (stats, complete)
    }
}
