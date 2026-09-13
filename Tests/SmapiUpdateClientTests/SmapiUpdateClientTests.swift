import Foundation
import Testing
@testable import StarHubTHCore

/// Une vérification smapi.io part en lots de 150 : le parc de référence en
/// demande **huit**. Le client rendait un succès nu indistinguable d'une passe
/// complète : l'appelant y posait l'horodatage de dernier succès, qui coupe la
/// vérification automatique pendant **douze heures**. X64 a donné à la passe
/// le moyen de dire ce qu'elle a **réellement couvert** ; X47 a fait qu'un lot
/// en échec n'arrête plus la boucle — on continue au suivant, et le fautif a
/// une seconde chance en fin de passe.
///
/// Ces tests épinglent les deux : ce que la passe a couvert, et ce qu'elle
/// récupère.
///
/// `.serialized` : le protocole d'URL simulé porte son script en statique, et
/// Swift Testing exécute les tests d'une suite en parallèle par défaut — deux
/// tests concurrents se voleraient leurs réponses.
@Suite(.serialized)
struct SmapiUpdateClientTests {

    // MARK: - Réseau simulé

    /// Rend la réponse programmée pour la n-ième requête reçue.
    private final class StubProtocol: URLProtocol {
        /// `(code HTTP, corps)` pour chaque requête, dans l'ordre.
        nonisolated(unsafe) static var script: [(Int, Data)] = []
        nonisolated(unsafe) static var received = 0
        private static let lock = NSLock()

        /// Quand posé, la **première** requête s'y bloque jusqu'au signal —
        /// l'épingle à « passe en vol, immobilisée à dessein » du test de
        /// sérialisation. `nil` dans tous les autres essais.
        nonisolated(unsafe) static var firstRequestGate: DispatchSemaphore?

        static func next() -> (Int, Data) {
            lock.lock(); defer { lock.unlock() }
            let step = received < script.count ? script[received] : (500, Data("[]".utf8))
            received += 1
            return step
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let (code, body) = Self.next()
            // Après consommation du script, donc `received == 1` dit « la
            // première requête est prise, sa réponse encore non rendue ».
            if let gate = Self.firstRequestGate, Self.received == 1 { gate.wait() }
            let response = HTTPURLResponse(url: request.url!, statusCode: code,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    /// `retryPause: 0` — le retrait de fin de passe (X47) n'est pas ce que
    /// ces tests éprouvent, et la production seule a cinq secondes à perdre.
    private func client(script: [(Int, Data)]) -> SmapiUpdateClient {
        StubProtocol.script = script
        StubProtocol.received = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        // `rateLimitPause: 0` (X87) — les tests programment des 503 et
        // comptent sur un cycle court : le mur de 30 s de la production
        // ferait timeout les tests avant que la completion n'arrive.
        return SmapiUpdateClient(session: URLSession(configuration: config),
                                 retryPause: 0, rateLimitPause: 0)
    }

    private func entries(_ count: Int, prefix: String = "mod") -> [SmapiUpdateRequest.Entry] {
        (0..<count).map { SmapiUpdateRequest.Entry(id: "\(prefix).\($0)",
                                                   updateKeys: ["Nexus:\(100 + $0)"],
                                                   installedVersion: "1.0.0") }
    }

    /// Un corps de réponse nommant les identifiants demandés — assez pour que
    /// le lot ne soit pas vu comme vide (ce qui déclencherait le re-découpage).
    private func body(for entries: [SmapiUpdateRequest.Entry]) -> Data {
        let items = entries.map { #"{"id":"\#($0.id)","errors":[]}"# }
        return Data("[\(items.joined(separator: ","))]".utf8)
    }

    private func fetch(_ client: SmapiUpdateClient,
                       entries: [SmapiUpdateRequest.Entry])
        -> Result<SmapiUpdateClient.Outcome, SmapiUpdateClient.Failure> {
        // `fetch` rend sur le fil principal ; les tests tournent hors de lui.
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        client.fetch(entries: entries, gameVersion: "1.6.15") { result in
            box.value = result
            done.signal()
        }
        _ = done.wait(timeout: .now() + 20)
        return box.value!
    }

    private final class Box {
        nonisolated(unsafe) var value: Result<SmapiUpdateClient.Outcome,
                                              SmapiUpdateClient.Failure>?
    }

    /// Sonde avec borne — jamais un sommeil nu : on attend une condition,
    /// on ne parie pas sur un calendrier. ⚠️ Appeler **hors** de `#expect` :
    /// le macro réécrit l'autoclosure et fige sa condition à sa première
    /// évaluation (constaté le 2026-09-13 — la sonde brûlait son timeout
    /// sur une condition déjà fausse tandis que le code, lui, répondait).
    private func waitUntil(_ condition: @autoclosure () -> Bool,
                           timeout: TimeInterval, step: UInt32 = 10_000) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { return false }
            usleep(step)
        }
        return true
    }

    // MARK: - Ce que la passe a couvert

    @Test func aCompletePassSaysSo() {
        let all = entries(300)          // deux lots de 150
        let first = Array(all[..<150])
        let second = Array(all[150...])
        let c = client(script: [(200, body(for: first)), (200, body(for: second))])
        guard case .success(let outcome) = fetch(c, entries: all) else {
            Issue.record("passe complète attendue en succès"); return
        }
        #expect(outcome.isComplete)
        #expect(outcome.batchesCompleted == 2)
        #expect(outcome.batchesTotal == 2)
        #expect(outcome.mods.count == 300)
    }

    @Test func aFailedBatchMakesThePassPartial() {
        // Le cas vécu : le premier lot répond, le second tombe en 503 — et sa
        // seconde chance aussi (le script épuisé rend 500 à toute requête
        // suivante). Les lots suivants partent (X47), échouent de même, et la
        // passe reste amputée : c'est ce que l'appelant doit voir.
        let all = entries(450)          // trois lots
        let first = Array(all[..<150])
        let c = client(script: [(200, body(for: first)), (503, Data())])
        guard case .success(let outcome) = fetch(c, entries: all) else {
            Issue.record("les 150 verdicts obtenus doivent être rendus"); return
        }
        #expect(outcome.mods.count == 150)
        #expect(outcome.batchesCompleted == 1)
        #expect(outcome.batchesTotal == 3)
        #expect(!outcome.isComplete)     // c'est ce qui manquait à l'appelant
    }

    @Test func aFirstBatchFailureIsStillAnError() {
        // Rien n'a abouti : l'appelant doit voir l'échec, pas une passe vide.
        let all = entries(300)
        let c = client(script: [(503, Data())])
        guard case .failure(let failure) = fetch(c, entries: all) else {
            Issue.record("échec attendu quand aucun lot n'aboutit"); return
        }
        guard case .http(let code) = failure else {
            Issue.record("code HTTP attendu"); return
        }
        #expect(code == 503)
    }

    /// X64 — le budget de re-découpage épuisé ne doit pas se faire passer pour
    /// une passe complète.
    ///
    /// Le re-découpage isole l'entrée que smapi.io refuse (200 + liste vide) ;
    /// son budget est de 32 requêtes pour toute la vérification. Au-delà, les
    /// sous-lots restants rendaient un tableau **vide** — et la boucle comptait
    /// le lot comme terminé. `isComplete` restait vrai, l'appelant posait son
    /// horodatage de succès, et jusqu'à 150 mods repartaient sans verdict pour
    /// douze heures. C'est exactement le défaut que `batchesCompleted` a été
    /// créé pour empêcher, par la porte de derrière : la branche « seule dans
    /// son lot » avait choisi de remonter une erreur plutôt que de se taire,
    /// celle-ci se taisait.
    ///
    /// Les trois champs connus pour vider un lot sont filtrés avant l'envoi
    /// (`isExpressibleVersion`, `sanitizedGameVersion`, `apiVersion` figée) —
    /// le filet reste pour le manifeste tiers qu'on ne contrôle pas.
    @Test func anExhaustedResplitBudgetDoesNotPassForACompleteCheck() {
        // Tout revient vide : le re-découpage descend jusqu'à épuiser son
        // budget bien avant d'avoir isolé les 150 entrées du premier lot.
        let all = entries(300)          // deux lots
        let c = client(script: Array(repeating: (200, Data("[]".utf8)), count: 200))
        guard case .success(let outcome) = fetch(c, entries: all) else {
            Issue.record("ce qui a été isolé doit être rendu, pas perdu"); return
        }
        #expect(!outcome.isComplete,
                "un budget épuisé laisse des mods sans verdict — la passe est amputée")
        #expect(outcome.batchesCompleted < outcome.batchesTotal)
        // Et ce que le re-découpage avait isolé avant l'épuisement survit :
        // troquer un abandon silencieux contre une perte totale referait le
        // défaut d'à côté.
        #expect(!outcome.mods.isEmpty,
                "les entrées isolées avant l'épuisement doivent être rendues")
    }

    @Test func anEmptyParkIsACompletePass() {
        // Zéro mod à vérifier n'est pas une passe amputée : rien à réessayer.
        let c = client(script: [])
        guard case .success(let outcome) = fetch(c, entries: []) else {
            Issue.record("succès attendu"); return
        }
        #expect(outcome.isComplete)
        #expect(outcome.mods.isEmpty)
        #expect(outcome.batchesTotal == 0)
    }

    // MARK: - X47 — un lot en échec ne sacrifie plus les suivants

    /// X47 — le `break` du premier lot fautif coûtait tous les suivants : un
    /// 503 ponctuel au lot 3 de 8 renonçait aux lots 4 à 8, que rien
    /// n'incriminait — 795 mods du parc de référence repartaient en reprise
    /// Nexus (quota compté) là où smapi.io les aurait couverts gratuitement.
    ///
    /// La politique : **continuer** au lot suivant, et offrir au lot fautif
    /// **une** seconde chance en fin de passe, après un retrait. Une seule :
    /// réessayer indéfiniment cognerait l'API publique gratuite que le code
    /// s'interdit déjà de paralléliser.
    @Test func aTransientFailureIsRetriedOnceAndThePassRecovers() {
        // Le lot 2 répond 503 ; le lot 3 part quand même ; le re-tri du lot 2
        // réussit. La passe redevient **complète** — c'est la récupération
        // que X47 achète.
        let all = entries(450)          // trois lots
        let first = Array(all[..<150])
        let second = Array(all[150..<300])
        let third = Array(all[300...])
        let c = client(script: [(200, body(for: first)),
                                (503, Data()),
                                (200, body(for: third)),
                                (200, body(for: second))],
                       )
        guard case .success(let outcome) = fetch(c, entries: all) else {
            Issue.record("succès attendu — la passe a récupéré"); return
        }
        #expect(outcome.isComplete)
        #expect(outcome.batchesCompleted == 3)
        #expect(outcome.mods.count == 450)
    }

    @Test func aLotThatFailsItsRetryLeavesThePassPartialAndNamesTheCause() {
        // Même scénario, mais le lot 2 échoue aussi à sa seconde chance : la
        // passe est amputée — et dit **pourquoi**, ce qu'un compte de lots
        // seul ne disait pas.
        let all = entries(450)
        let first = Array(all[..<150])
        let third = Array(all[300...])
        let c = client(script: [(200, body(for: first)),
                                (503, Data()),
                                (200, body(for: third)),
                                (503, Data())],               // le lot 2, retenté
                       )
        guard case .success(let outcome) = fetch(c, entries: all) else {
            Issue.record("les 300 verdicts obtenus doivent être rendus"); return
        }
        #expect(!outcome.isComplete)
        #expect(outcome.batchesCompleted == 2)
        #expect(outcome.mods.count == 300)
        guard case .http(503)? = outcome.failure else {
            Issue.record("la cause de l'amputation doit être nommée : \(String(describing: outcome.failure))")
            return
        }
    }

    @Test func aDecodingFailureIsNotRetried() {
        // Une erreur de décodage est déterministe : les mêmes octets
        // reviendront. La retenter dépenserait une requête contre une API
        // publique gratuite pour n'apprendre rien de nouveau — on note
        // l'échec, on continue, sans seconde chance.
        let all = entries(450)
        let first = Array(all[..<150])
        let third = Array(all[300...])
        let c = client(script: [(200, body(for: first)),
                                (200, Data("pas du JSON".utf8)),   // lot 2 : décodage
                                (200, body(for: third))],
                       )
        guard case .success(let outcome) = fetch(c, entries: all) else {
            Issue.record("les 300 verdicts obtenus doivent être rendus"); return
        }
        #expect(!outcome.isComplete)
        #expect(outcome.batchesCompleted == 2)
        guard case .decoding? = outcome.failure else {
            Issue.record("la cause doit être un échec de décodage"); return
        }
        // Trois requêtes, pas une de plus : le lot fautif n'a pas été retenté.
        #expect(StubProtocol.received == 3)
    }

    /// X87 : un 429 sur un lot ne doit pas déclencher un retry immédiat du
    /// suivant. Le mur de rate-limit s'arme pour `rateLimitPause` secondes
    /// (30 en production) ; les tests le court-circuitent à 0 mais valident
    /// que **le 429 arme bien le mur** (les requêtes suivantes voient
    /// l'effet dans le timing d'envoi).
    @Test func aRateLimitedBatchArmsTheBackoff() {
        let all = entries(300)
        let first = Array(all[..<150])
        let c = client(script: [(429, Data()),
                                (200, body(for: Array(all[150...]))),
                                (200, body(for: first))])
        // Le script rendra 3 réponses, dans l'ordre : lot 1 = 429 (mur armé),
        // lot 2 = 200, lot 3 = 200 (la seconde chance). Avec
        // `rateLimitPause: 0`, l'attente est nulle et le test reste
        // déterministe ; ce qui compte est que les 3 requêtes partent.
        guard case .success = fetch(c, entries: all) else {
            Issue.record("les 150 verdicts du lot 2 doivent être rendus"); return
        }
        #expect(StubProtocol.received == 3)
    }

    // MARK: - X87 — la sérialisation des appels et le retour du créneau

    /// Deux `fetch` qui se chevauchent ne doivent jamais doubler la charge
    /// **en parallèle** (X87) : le second attend la passe en vol, puis
    /// repart — séquentiellement, jamais entremêlé. Et la passe doit rendre
    /// son créneau en finissant (le nettoyage de `inFlight`) : sinon tout
    /// appel suivant attendrait une tâche morte en boucle, et sa complétion
    /// ne partirait jamais.
    ///
    /// L'épingle à « passe en vol » est volontaire : la première requête se
    /// bloque sur un sémaphore tenu par le test. Tant qu'il est tenu, la
    /// passe de tête ne peut rien envoyer de plus — toute requête qui
    /// pointerait pendant la fenêtre d'observation ne peut venir que d'une
    /// seconde passe partie en parallèle, c'est-à-dire du défaut.
    @Test func anOverlappingCallWaitsItsTurnAndTheSlotIsReturned() {
        let all = entries(300)          // deux lots de 150
        let first = Array(all[..<150])
        let second = Array(all[150...])
        let gate = DispatchSemaphore(value: 0)
        StubProtocol.firstRequestGate = gate
        defer { StubProtocol.firstRequestGate = nil }
        let c = client(script: [(200, body(for: first)), (200, body(for: second))])

        let headBox = Box()
        let tailBox = Box()
        let headDone = DispatchSemaphore(value: 0)
        let tailDone = DispatchSemaphore(value: 0)
        c.fetch(entries: all, gameVersion: "1.6.15") { headBox.value = $0; headDone.signal() }
        c.fetch(entries: all, gameVersion: "1.6.15") { tailBox.value = $0; tailDone.signal() }

        // La passe de tête est bien engagée — et bloquée à dessein.
        let engaged = waitUntil(StubProtocol.received == 1, timeout: 5)
        #expect(engaged, "la passe de tête doit engager sa première requête")
        // Fenêtre d'observation : 0,3 s où la passe de tête, bloquée, ne peut
        // rien envoyer de plus. Toute requête de plus pendant la fenêtre vient
        // d'un chevauchement.
        var quietWindow = true
        let windowEnd = Date().addingTimeInterval(0.3)
        while Date() < windowEnd {
            if StubProtocol.received != 1 { quietWindow = false; break }
            usleep(10_000)
        }
        #expect(quietWindow,
                "aucune requête ne doit partir pendant que la passe de tête est en vol")
        gate.signal()

        // La passe de tête, intacte : ses deux lots, ses 300 verdicts.
        #expect(headDone.wait(timeout: .now() + 10) == .success)
        guard case .success(let head)? = headBox.value else {
            Issue.record("la passe de tête doit réussir en entier"); return
        }
        #expect(head.isComplete)
        #expect(head.mods.count == 300)

        // Le second appel rend SA complétion — jamais perdue : sa re-passe,
        // sérialisée après la première, a tourné jusqu'au bout (le script
        // épuisé lui rend des 500 ; son verdict exact n'est pas ce que le
        // test épingle — ce qui compte est qu'elle a tourné et rendu).
        #expect(tailDone.wait(timeout: .now() + 10) == .success,
                "la complétion du second appel ne doit jamais se perdre")
        // La re-passe de queue a bien tourné : au moins ses deux lots en
        // plus des deux de la tête. (Le compte exact dépend de la politique
        // de retrait X47 — deux 500 transitoires repartent une fois chacun,
        // soit 6 au total — et n'est pas ce que ce test épingle.)
        #expect(StubProtocol.received >= 4)
    }
}
