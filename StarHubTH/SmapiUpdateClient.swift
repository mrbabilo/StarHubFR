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

    /// Verrou anti-double-appel. `fetch` peut être appelé plusieurs fois
    /// (vérification auto + bouton manuel de l'utilisateur pendant qu'une
    /// passe est en cours) ; sans verrou, deux `Task` partiraient en
    /// parallèle et doubleraient la charge sur l'API publique.
    private var inFlight: Task<Void, Never>?
    private let inFlightLock = NSLock()

    /// Ce qu'une vérification a **réellement couvert**.
    ///
    /// Rendre les seuls verdicts obtenus ne suffit pas : un succès nu est
    /// indistinguable d'une passe complète, et l'appelant y posait alors
    /// l'horodatage de dernier succès, qui coupe la vérification automatique
    /// pendant douze heures (`UpdateCheckPolicy`).
    ///
    /// Depuis X47, un lot en échec n'arrête plus la boucle : on continue au
    /// suivant et on retente le fautif une fois en fin de passe. Une passe
    /// reste donc amputée seulement si un lot a échoué **deux fois** — ou si
    /// le budget de re-découpage s'est épuisé (X64).
    struct Outcome {
        let mods: [SmapiUpdateResponse.Mod]
        /// Lots effectivement envoyés **et** revenus.
        let batchesCompleted: Int
        let batchesTotal: Int
        /// La **première** défaillance de lot, quand la passe est amputée.
        /// Un compte de lots seul ne dit pas pourquoi — le journal de
        /// l'appelant, lui, doit le dire.
        var failure: Failure?
        /// Un parc vide (zéro lot) est complet : il n'y a rien à réessayer.
        var isComplete: Bool { batchesCompleted >= batchesTotal }
    }

    init(session: URLSession = .shared, retryPause: TimeInterval = 5) {
        self.session = session
        self.retryPause = retryPause
        self.rateLimitPause = 30
    }

    /// Constructeur de test — `retryPause: 0` court-circuite le retrait de
    /// fin de passe ; `rateLimitPause: 0` court-circuite le mur de
    /// rate-limit. X87 veut qu'on respecte le mur en production, mais
    /// les tests programment des 503 et comptent sur un cycle court.
    init(session: URLSession, retryPause: TimeInterval, rateLimitPause: TimeInterval) {
        self.session = session
        self.retryPause = retryPause
        self.rateLimitPause = rateLimitPause
    }

    private let retryPause: TimeInterval
    private let rateLimitPause: TimeInterval

    /// - Parameters:
    ///   - progress: `(lots terminés, lots au total)`, sur le fil principal.
    ///   - completion: sur le fil principal.
    func fetch(entries: [SmapiUpdateRequest.Entry],
               gameVersion: String,
               progress: ((Int, Int) -> Void)? = nil,
               completion: @escaping (Result<Outcome, Failure>) -> Void) {
        // X87 : sérialiser les appels concurrents. Sans ce verrou, un
        // déclenchement automatique (UpdateCheckPolicy) qui tomberait
        // pendant qu'une vérification manuelle est en cours doublerait la
        // charge sur l'API. La `Task` antérieure est attendue par
        // `await inFlight?.value` : on ne perd pas son résultat, on
        // attend qu'elle finisse.
        inFlightLock.lock()
        if let existing = inFlight {
            inFlightLock.unlock()
            Task {
                _ = await existing.value
                await MainActor.run { [entries, gameVersion, progress, completion] in
                    self.fetch(entries: entries, gameVersion: gameVersion,
                               progress: progress, completion: completion)
                }
            }
            return
        }
        let task = Task { [entries, gameVersion, progress, completion] in
            await self.runFetch(entries: entries, gameVersion: gameVersion,
                                progress: progress, completion: completion)
        }
        inFlight = task
        inFlightLock.unlock()
        Task {
            await task.value
            self.inFlightLock.lock()
            self.inFlight = nil
            self.inFlightLock.unlock()
        }
    }

    /// Le corps du fetch, isolé pour que `fetch` puisse l'attendre et le
    /// ré-enchaîner sans dupliquer sa logique. X87 : un mur de
    /// rate-limit (`rateLimitUntil`) est respecté entre chaque lot —
    /// sans lui, un 503 suivi d'un retry immédiat aggrave la situation
    /// au lieu de la laisser respirer.
    private func runFetch(entries: [SmapiUpdateRequest.Entry],
                          gameVersion: String,
                          progress: ((Int, Int) -> Void)? = nil,
                          completion: @escaping (Result<Outcome, Failure>) -> Void) async {
        let batches = SmapiUpdateRequest.batches(entries, size: batchSize)
        guard !batches.isEmpty else {
            await MainActor.run {
                completion(.success(Outcome(mods: [], batchesCompleted: 0,
                                            batchesTotal: 0, failure: nil)))
            }
            return
        }

        var collected: [SmapiUpdateResponse.Mod] = []
        /// Index des lots en échec, et l'erreur vue — la **première**
        /// vue pour la passe entière, pour un verdict déterministe.
        var batchFailures: [Int: Failure] = [:]
        var firstFailure: Failure?
        var completed = Set<Int>()

        // Les lots partent en série : la charge est déjà groupée, et une
        // rafale parallèle sur une API publique gratuite ne gagnerait que
        // le risque de se faire fermer la porte.
        // Le budget de re-découpage, pour **toute** la vérification.
        // Voir `collect(batch:gameVersion:budget:)`.
        var budget = Self.resplitBudget
        for (index, batch) in batches.enumerated() {
            // X87 : si un 429/503 a armé le mur pendant un lot précédent,
            // attendre ici plutôt que de partir tout de suite. L'attente
            // est `try?` : une annulation (sortie d'app) ne nous bloque
            // pas, et on saute au lot suivant si le mur n'est pas levé.
            if let until = rateLimitUntil, until > Date() {
                let wait = until.timeIntervalSinceNow
                if wait > 0, wait < self.rateLimitPause * 2 {
                    do { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                    catch { continue }
                }
            }
            // X47 — un lot en échec ne sacrifie plus les suivants : on le
            // note, on continue. Le fautif aura sa seconde chance en fin
            // de passe. Sur les huit lots du parc de référence, l'ancien
            // `break` livrait jusqu'à 795 mods à la reprise Nexus (quota
            // compté) pour un 503 qui ne les concernait pas.
            do {
                let outcome = try await collect(batch: batch, gameVersion: gameVersion,
                                                budget: budget)
                collected += outcome.mods
                budget = outcome.budgetLeft
                // Ce qui a été isolé avant l'épuisement est gardé (ligne
                // au-dessus), mais le lot n'est pas terminé : il ne compte
                // pas. Les suivants partent quand même : un budget épuisé
                // condamne le re-découpage, pas les lots sains — chacun
                // d'eux coûte une requête et peut très bien revenir.
                if outcome.abandoned { continue }
            } catch let error as Failure {
                batchFailures[index] = error
                if firstFailure == nil { firstFailure = error }
                continue
            } catch {
                batchFailures[index] = .transport(error.localizedDescription)
                if firstFailure == nil {
                    firstFailure = .transport(error.localizedDescription)
                }
                continue
            }
            completed.insert(index)
            // `let` local : la progression ne peut pas emporter un `var`
            // capturé dans une closure concurrente.
            let done = completed.count
            await MainActor.run { progress?(done, batches.count) }
        }

        // La seconde chance (X47) : après un retrait, **une** tentative de
        // plus pour les lots victimes d'un accident — transport ou HTTP.
        // Une erreur de décodage est déterministe : les mêmes octets
        // reviendraient, la retenter dépenserait une requête contre une
        // API publique gratuite pour n'apprendre rien de nouveau.
        let transient = batchFailures
            .filter { if case .decoding = $0.value { return false } else { return true } }
            .sorted { $0.key < $1.key }
        // Le retrait. Une annulation (la tâche n'a plus d'auditoire —
        // sortie de l'app) dit que la seconde chance n'a pas à partir :
        // l'avaler et retenter quand même serait pire que le silence.
        var retryRound = transient
        if !transient.isEmpty, retryPause > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(retryPause * 1_000_000_000))
            } catch {
                retryRound = []
            }
        }
        for (index, _) in retryRound {
            do {
                let outcome = try await collect(batch: batches[index],
                                                gameVersion: gameVersion,
                                                budget: budget)
                collected += outcome.mods
                budget = outcome.budgetLeft
                if outcome.abandoned { continue }
            } catch let error as Failure {
                batchFailures[index] = error
                continue
            } catch {
                batchFailures[index] = .transport(error.localizedDescription)
                continue
            }
            batchFailures[index] = nil
            completed.insert(index)
            let done = completed.count
            await MainActor.run { progress?(done, batches.count) }
        }

        // Des lots en échec après des lots réussis rendent quand même ce
        // qui a abouti : perdre 800 verdicts parce que le dernier lot a
        // échoué serait le défaut qu'on corrige, sous une autre forme.
        // Mais la passe **dit** qu'elle est amputée — et pourquoi :
        // `Outcome.isComplete` empêche l'appelant de la prendre pour un
        // passage réussi du parc entier, `Outcome.failure` nomme la cause.
        let completedBatches = completed.count
        let outcome: Result<Outcome, Failure> =
            (firstFailure != nil && completedBatches == 0 && collected.isEmpty)
            ? .failure(firstFailure!)
            : .success(Outcome(mods: collected,
                               batchesCompleted: completedBatches,
                               batchesTotal: batches.count,
                               failure: firstFailure))
        await MainActor.run { completion(outcome) }
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
        // X87 : 429 / 503 sont des signaux de rate-limit. Plutôt que de
        // relancer le lot tout de suite, on lève un **mur** que la boucle
        // `fetch` lira et respectera. L'erreur remonte comme n'importe
        // quel `Failure.http` ; le mur s'exprime à côté. La double
        // information est volontaire : un 503 suivi d'un mur de 30 s a
        // la même signature dans le journal qu'un 503 d'un serveur en
        // panne, mais le mur protège contre la première des deux sans
        // masquer la seconde (un 5xx non-rate-limit ne lève pas de mur).
        guard http.statusCode == 200 else {
            if (429...429).contains(http.statusCode) || (503...503).contains(http.statusCode) {
                rateLimitUntil = Date().addingTimeInterval(self.rateLimitPause)
            }
            throw Failure.http(http.statusCode)
        }
        do {
            return try SmapiUpdateResponse.decode(data)
        } catch {
            throw Failure.decoding(error.localizedDescription)
        }
    }

    /// L'horodatage avant lequel les requêtes smapi.io ne doivent pas partir
    /// (X87). Lu par `fetch` avant chaque lot. Pas de NSLock : `post` est
    /// `await`-borne par `session.data`, et les mutations de cette propriété
    /// arrivent séquentiellement dans la même `Task` que les lectures de
    /// `fetch`. Un appel `fetch` concurrent passe par `inFlight`, mutex
    /// séparé.
    ///
    /// Durée du mur : `rateLimitPause` (30 s en production, 0 dans les
    /// tests). smapi.io ne documente pas de header `Retry-After` formel ;
    /// on s'aligne sur l'observation X87 : un 429 suivi d'un délai
    /// d'au moins 5 s est accepté, un retry immédiat est refusé. 30 s
    /// laisse une vraie respiration sans transformer une panne
    /// transitoire en blocage de 5 minutes.
    private var rateLimitUntil: Date?
}
