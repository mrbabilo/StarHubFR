import Foundation

/// Le réseau de la vitrine et des recherches : GraphQL v2.
///
/// Le réseau seulement : la construction des requêtes et la lecture des
/// réponses vivent dans `NexusModSearch` (Core, testé). Ce fichier ne fait
/// que poster et rapporter.
///
/// ⚠️ **L'API v2 ne renvoie aucun en-tête `x-rl-*`** — vérifié le 2026-08-25 :
/// le quota affiché dans les réglages (B2-T6) ne dit donc rien des recherches.
/// Le relevé est quand même branché : une réponse muette laisse la mesure
/// précédente intacte, et le jour où Nexus ajoutera ces en-têtes, le compte
/// suivra sans qu'on y revienne.
enum NexusSearchClient {
    enum SearchError: Error {
        case noApiKey
        case rateLimited(retryAfter: TimeInterval)
        case transport(String)
        case http(Int)
        case read(NexusModSearch.Failure)
    }

    /// Cherche les mods dont le nom contient `name`.
    ///
    /// - Parameter completion: appelé **sur le fil principal**.
    /// - Parameter tag: restreint au tag Nexus donné — `NexusModSearch.frenchTag`
    ///   pour ne rendre que les traductions françaises. `nil` cherche large.
    static func search(name: String, tag: String? = nil,
                       completion: @escaping (Result<NexusModSearch.Page, SearchError>) -> Void) {
        send(body: NexusModSearch.queryBody(name: name,
                                            gameId: NexusRequestBuilder.gameId,
                                            tag: tag),
             decode: NexusModSearch.decode,
             completion: completion)
    }

    /// Les mods du jeu par tri — la vitrine « Découvrir » (spec §5.1).
    ///
    /// - Parameter tag: restreint au tag Nexus donné — la sélection FR.
    /// - Parameter category: restreint à une catégorie Nexus, par son **nom
    ///   anglais** (`NexusCategory.englishName`) : c'est ce que le filtre
    ///   `categoryName` attend, et le seul que l'API connaisse.
    static func listing(sort: NexusModSearch.ListingSort, tag: String? = nil,
                        category: String? = nil,
                        completion: @escaping (Result<NexusModSearch.Page, SearchError>) -> Void) {
        send(body: NexusModSearch.listingBody(sort: sort, tag: tag, category: category,
                                              gameId: NexusRequestBuilder.gameId),
             decode: NexusModSearch.decode,
             completion: completion)
    }

    /// La fiche d'un mod (spec §5.2).
    static func detail(modId: Int,
                       completion: @escaping (Result<NexusModSearch.Detail, SearchError>) -> Void) {
        send(body: NexusModSearch.detailBody(modId: modId,
                                             gameId: NexusRequestBuilder.gameId),
             decode: NexusModSearch.decodeDetail,
             completion: completion)
    }

    /// L'entonnoir commun : clé, requête, quota, 429, 200-avec-`errors`.
    /// Une seule copie pour la recherche, le listing et la fiche — pas de
    /// variantes qui divergent.
    private static func send<T>(body: Data?,
                                decode: @escaping (Data) -> Result<T, NexusModSearch.Failure>,
                                completion: @escaping (Result<T, SearchError>) -> Void) {
        func finish(_ result: Result<T, SearchError>) {
            DispatchQueue.main.async { completion(result) }
        }
        guard let apiKey = NexusUpdateChecker.shared.apiKey(), !apiKey.isEmpty else {
            finish(.failure(.noApiKey)); return
        }
        guard let body,
              let request = NexusRequestBuilder.makeGraphQLRequest(body: body, apiKey: apiKey)
        else {
            finish(.failure(.transport("invalid_request"))); return
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                finish(.failure(.transport(error.localizedDescription))); return
            }
            if let http = response as? HTTPURLResponse {
                // Même entonnoir que les appels v1 : sans en-tête de quota la
                // mesure précédente reste en place, et un 429 freine tout le
                // monde plutôt que la seule recherche.
                NexusUpdateChecker.shared.noteQuota(from: http)
                if http.statusCode == 429 {
                    finish(.failure(.rateLimited(retryAfter: 60))); return
                }
                guard (200..<300).contains(http.statusCode) else {
                    finish(.failure(.http(http.statusCode))); return
                }
            }
            guard let data else {
                finish(.failure(.transport("empty_response"))); return
            }
            // Un 200 ne suffit pas à conclure : GraphQL rend 200 avec un
            // tableau `errors`, et le prendre pour un résultat vide changerait
            // une panne de schéma en « aucune traduction trouvée ».
            switch decode(data) {
            case .success(let value): finish(.success(value))
            case .failure(let failure): finish(.failure(.read(failure)))
            }
        }.resume()
    }
}
