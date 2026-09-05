import Foundation
import Testing
@testable import StarHubTHCore

/// Une vérification smapi.io part en lots de 150 : le parc de référence en
/// demande **huit**. Le premier lot en échec arrête la boucle — les suivants ne
/// partent jamais — et le client rendait malgré tout un succès, indistinguable
/// d'une passe complète. L'appelant y posait alors l'horodatage de dernier
/// succès, qui coupe la vérification automatique pendant **douze heures** : un
/// 503 sur le troisième lot laissait jusqu'à 795 mods sans avoir été interrogés
/// une seule fois, sans rien dans le journal, et sans nouvelle tentative.
///
/// Ces tests épinglent ce que la passe a **réellement couvert**.
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
            let response = HTTPURLResponse(url: request.url!, statusCode: code,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func client(script: [(Int, Data)]) -> SmapiUpdateClient {
        StubProtocol.script = script
        StubProtocol.received = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return SmapiUpdateClient(session: URLSession(configuration: config))
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
        // Le cas vécu : le premier lot répond, le second tombe en 503. La
        // boucle s'arrête là — les lots suivants ne partent pas.
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
}
