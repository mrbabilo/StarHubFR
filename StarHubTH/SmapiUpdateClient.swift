import Foundation

/// Le seul fichier qui parle à smapi.io.
///
/// Aucune décision ici : la construction de la requête vit dans
/// `SmapiUpdateRequest`, le décodage et le classement des erreurs dans
/// `SmapiUpdateResponse`, tous deux testés. Ce fichier ne fait que poster des
/// lots et rassembler les réponses.
///
/// Ni clé d'API ni quota : c'est la source publique que SMAPI consulte
/// lui-même au démarrage.
final class SmapiUpdateClient {
    static let shared = SmapiUpdateClient()

    /// 150 : la taille mesurée comme sûre sur un parc de 960 mods (7 lots,
    /// réponse complète). Un lot unique de 960 n'a pas été éprouvé.
    private let batchSize = 150
    private let endpoint = URL(string: "https://smapi.io/api/v3.0/mods")!
    private let session: URLSession

    enum Failure: Error {
        case transport(String)
        case http(Int)
        case decoding(String)
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// - Parameters:
    ///   - progress: `(lots terminés, lots au total)`, sur le fil principal.
    ///   - completion: sur le fil principal.
    func fetch(entries: [SmapiUpdateRequest.Entry],
               gameVersion: String,
               progress: ((Int, Int) -> Void)? = nil,
               completion: @escaping (Result<[SmapiUpdateResponse.Mod], Failure>) -> Void) {
        let batches = SmapiUpdateRequest.batches(entries, size: batchSize)
        guard !batches.isEmpty else {
            Task { @MainActor in completion(.success([])) }
            return
        }

        Task {
            var collected: [SmapiUpdateResponse.Mod] = []
            var failure: Failure?

            // Les lots partent en série : la charge est déjà groupée, et une
            // rafale parallèle sur une API publique gratuite ne gagnerait que
            // le risque de se faire fermer la porte.
            for (index, batch) in batches.enumerated() {
                do {
                    collected += try await post(batch: batch, gameVersion: gameVersion)
                } catch let error as Failure {
                    failure = error
                    break
                } catch {
                    failure = .transport(error.localizedDescription)
                    break
                }
                let done = index + 1
                await MainActor.run { progress?(done, batches.count) }
            }

            // Un lot en échec après des lots réussis rend quand même ce qui a
            // abouti : perdre 800 verdicts parce que le dernier lot a échoué
            // serait le défaut qu'on vient de corriger, sous une autre forme.
            let outcome: Result<[SmapiUpdateResponse.Mod], Failure> =
                (failure != nil && collected.isEmpty) ? .failure(failure!) : .success(collected)
            await MainActor.run { completion(outcome) }
        }
    }

    private func post(batch: [SmapiUpdateRequest.Entry],
                      gameVersion: String) async throws -> [SmapiUpdateResponse.Mod] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(NexusRequestBuilder.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        let body = SmapiUpdateRequest.Body(mods: batch, gameVersion: gameVersion)
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw Failure.decoding(error.localizedDescription)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure.transport("no_response")
        }
        guard http.statusCode == 200 else {
            throw Failure.http(http.statusCode)
        }
        do {
            return try SmapiUpdateResponse.decode(data)
        } catch {
            throw Failure.decoding(error.localizedDescription)
        }
    }
}
