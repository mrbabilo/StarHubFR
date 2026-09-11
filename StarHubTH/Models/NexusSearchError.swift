import Foundation

/// Ce qui peut rater quand on interroge la recherche Nexus.
///
/// Vit en Core, séparé de `NexusSearchClient` qui fait le réseau : l'état de
/// la vitrine (`DiscoveryStore`) porte la dernière panne, et un store testable
/// ne peut pas dépendre d'un client réseau. `NexusSearchClient.SearchError`
/// reste un alias — les appelants ne changent pas.
public enum NexusSearchError: Error {
    case noApiKey
    case rateLimited(retryAfter: TimeInterval)
    case transport(String)
    case http(Int)
    case read(NexusModSearch.Failure)
}
