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

    /// Ce qu'une vérification a **réellement couvert**.
    ///
    /// Rendre les seuls verdicts obtenus ne suffit pas : le premier lot en
    /// échec arrête la boucle, les suivants ne partent jamais, et un succès nu
    /// est indistinguable d'une passe complète. L'appelant y posait alors
    /// l'horodatage de dernier succès, qui coupe la vérification automatique
    /// pendant douze heures (`UpdateCheckPolicy`) : sur les huit lots du parc
    /// de référence, un 503 au troisième laissait jusqu'à 795 mods jamais
    /// interrogés, sans rien au journal et sans nouvelle tentative.
    struct Outcome {
        let mods: [SmapiUpdateResponse.Mod]
        /// Lots effectivement envoyés **et** revenus.
        let batchesCompleted: Int
        let batchesTotal: Int
        /// Un parc vide (zéro lot) est complet : il n'y a rien à réessayer.
        var isComplete: Bool { batchesCompleted >= batchesTotal }
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
               completion: @escaping (Result<Outcome, Failure>) -> Void) {
        let batches = SmapiUpdateRequest.batches(entries, size: batchSize)
        guard !batches.isEmpty else {
            Task { @MainActor in
                completion(.success(Outcome(mods: [], batchesCompleted: 0, batchesTotal: 0)))
            }
            return
        }

        Task {
            var collected: [SmapiUpdateResponse.Mod] = []
            var failure: Failure?
            var completedBatches = 0

            // Les lots partent en série : la charge est déjà groupée, et une
            // rafale parallèle sur une API publique gratuite ne gagnerait que
            // le risque de se faire fermer la porte.
            // Le budget de re-découpage, pour **toute** la vérification.
            // Voir `collect(batch:gameVersion:budget:)`.
            var budget = Self.resplitBudget
            for (index, batch) in batches.enumerated() {
                do {
                    let outcome = try await collect(batch: batch, gameVersion: gameVersion,
                                                    budget: budget)
                    collected += outcome.mods
                    budget = outcome.budgetLeft
                    // Ce qui a été isolé avant l'épuisement est gardé (ligne
                    // au-dessus), mais le lot n'est pas terminé : on s'arrête
                    // sans le compter. Un budget épuisé signale de toute façon
                    // une cause qui ne s'arrêtera pas au lot suivant.
                    if outcome.abandoned { break }
                } catch let error as Failure {
                    failure = error
                    break
                } catch {
                    failure = .transport(error.localizedDescription)
                    break
                }
                completedBatches = index + 1
                // `let` local : `completedBatches` est un `var` capturé, ce
                // qu'une closure concurrente ne peut pas emporter.
                let done = completedBatches
                await MainActor.run { progress?(done, batches.count) }
            }

            // Un lot en échec après des lots réussis rend quand même ce qui a
            // abouti : perdre 800 verdicts parce que le dernier lot a échoué
            // serait le défaut qu'on vient de corriger, sous une autre forme.
            // Mais la passe **dit** qu'elle est amputée : `Outcome.isComplete`
            // est ce qui permet à l'appelant de ne pas la prendre pour un
            // passage réussi du parc entier.
            let outcome: Result<Outcome, Failure> =
                (failure != nil && collected.isEmpty)
                ? .failure(failure!)
                : .success(Outcome(mods: collected,
                                   batchesCompleted: completedBatches,
                                   batchesTotal: batches.count))
            await MainActor.run { completion(outcome) }
        }
    }

    /// Le nombre de requêtes **supplémentaires** qu'une vérification peut
    /// dépenser à re-découper des lots vides.
    ///
    /// Isoler une entrée toxique dans un lot de 150 en coûte une quinzaine ; le
    /// budget en laisse passer deux. Au-delà, la cause n'est plus une entrée
    /// mais un champ global de la requête — `gameVersion` ou `apiVersion`
    /// malformée vide *tous* les lots — et poursuivre le découpage lancerait
    /// deux mille requêtes contre une API publique gratuite pour n'apprendre
    /// que ce qu'un journal dit en une ligne.
    private static let resplitBudget = 32

    /// Rend les réponses d'un lot, en le **re-découpant** s'il revient vide.
    ///
    /// smapi.io répond `200` et une **liste vide** quand une seule entrée du
    /// lot lui déplaît : les 149 autres repartent sans verdict, sans erreur, et
    /// sans que rien ne le dise. Mesuré sur le parc réel le 2026-08-27 —
    /// `Wesley.ArtisanQualityInOut` livre `Version: "%ProjectVersion%"`, et le
    /// lot entier disparaît. Le mod est en pause : le jeu ne le charge même
    /// pas.
    ///
    /// Le re-découpage descend dans les **deux** moitiés sans s'arrêter à la
    /// première fautive : la source du poison est un manifeste tiers, il y en
    /// aura d'autres, et rien ne garantit qu'ils tombent dans des lots
    /// différents.
    ///
    /// Un lot sain coûte une requête, exactement comme avant.
    private func collect(batch: [SmapiUpdateRequest.Entry],
                         gameVersion: String,
                         budget: Int) async throws -> (mods: [SmapiUpdateResponse.Mod],
                                                       budgetLeft: Int,
                                                       abandoned: Bool) {
        let answers = try await post(batch: batch, gameVersion: gameVersion)
        guard answers.isEmpty, !batch.isEmpty else { return (answers, budget, false) }
        guard batch.count > 1 else {
            // Seule dans son lot et toujours rien : c'est elle. La remonter en
            // erreur plutôt que de la laisser disparaître : un mod passé sous
            // silence est exactement le défaut que cette fonction répare.
            return ([SmapiUpdateResponse.Mod(id: batch[0].id,
                                             errors: [SmapiUpdateResponse.rejectedEntryError])],
                    budget, false)
        }
        // Budget épuisé : les entrées de ce sous-lot resteront sans verdict.
        // Le dire — `abandoned` remonte jusqu'à `fetch`, qui refuse alors de
        // compter le lot comme terminé. Rendre un tableau vide en silence
        // faisait passer 287 mods sur 300 à la trappe *et* déclarait la passe
        // complète : l'appelant posait son horodatage de succès et ne
        // revérifiait pas avant douze heures. La branche « seule dans son
        // lot » avait déjà tranché de ne pas se taire ; celle-ci s'aligne.
        guard budget >= 2 else { return ([], budget, true) }
        let half = batch.count / 2
        let left = try await collect(batch: Array(batch[..<half]),
                                     gameVersion: gameVersion, budget: budget - 2)
        let right = try await collect(batch: Array(batch[half...]),
                                      gameVersion: gameVersion, budget: left.budgetLeft)
        return (left.mods + right.mods, right.budgetLeft, left.abandoned || right.abandoned)
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
