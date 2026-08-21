import Foundation
import Testing
@testable import StarHubTHCore

/// L'ordre des tentatives. Le stub route selon l'hôte : loopback = l'IA
/// locale, `deepl.com` = le secours. Sérialisée : le stub vit dans des
/// `static`.
@Suite(.serialized)
struct TranslationEngineTests {

    private final class Stub: URLProtocol {
        nonisolated(unsafe) static var localReply: String?
        nonisolated(unsafe) static var deepLReply: String?
        nonisolated(unsafe) static var deepLStatus = 200
        nonisolated(unsafe) static var deepLCalls = 0

        static func reset() {
            localReply = nil
            deepLReply = nil
            deepLStatus = 200
            deepLCalls = 0
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            let isDeepL = request.url?.host?.contains("deepl.com") == true
            if isDeepL { Self.deepLCalls += 1 }
            let text = isDeepL ? Self.deepLReply : Self.localReply
            guard let text else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            let status = isDeepL ? Self.deepLStatus : 200
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }

    private func localCompletion(_ text: String) -> String {
        #"{"choices":[{"finish_reason":"stop","message":{"content":"\#(text)"}}]}"#
    }

    private func deepL(_ text: String) -> String {
        #"{"translations":[{"text":"\#(text)"}]}"#
    }

    private var request: LocalLLMClient.Request {
        LocalLLMClient.Request(model: "m", source: "Hi {{Name}}!",
                               glossary: [], sectionLabel: nil)
    }

    private let local = URL(string: "http://127.0.0.1:11434")!
    private let key = DeepLClient.Credentials(key: "k:fx")!

    /// Le local réussit : le secours ne part pas. C'est la garantie de fond —
    /// rien ne sort quand rien n'a échoué.
    @Test func aLocalSuccessNeverReachesTheFallback() async {
        Stub.reset()
        Stub.localReply = localCompletion("Salut {{Name}} !")
        let outcome = await TranslationEngine.translate(
            request, localBaseURL: local, localSession: session(),
            fallback: key, fallbackSession: session())
        #expect(outcome == .translated("Salut {{Name}} !", by: .local))
        #expect(Stub.deepLCalls == 0)
    }

    @Test func anUnreachableLocalServerFallsBack() async {
        Stub.reset()
        Stub.deepLReply = deepL("Salut <x>{{Name}}</x> !")
        let outcome = await TranslationEngine.translate(
            request, localBaseURL: local, localSession: session(),
            fallback: key, fallbackSession: session())
        #expect(outcome == .translated("Salut {{Name}} !", by: .fallback))
        #expect(Stub.deepLCalls == 1)
    }

    /// Le modèle a rendu une traduction amputée d'une marque dure : c'est
    /// l'autre déclencheur.
    @Test func aLocalTokenRefusalFallsBack() async {
        Stub.reset()
        Stub.localReply = localCompletion("Salut !")          // {{Name}} perdu
        Stub.deepLReply = deepL("Salut <x>{{Name}}</x> !")
        let outcome = await TranslationEngine.translate(
            request, localBaseURL: local, localSession: session(),
            fallback: key, fallbackSession: session())
        #expect(outcome == .translated("Salut {{Name}} !", by: .fallback))
    }

    @Test func withoutCredentialsTheLocalOutcomePassesThrough() async {
        Stub.reset()
        let outcome = await TranslationEngine.translate(
            request, localBaseURL: local, localSession: session(),
            fallback: nil, fallbackSession: session())
        guard case .endpointError = outcome else {
            Issue.record("attendu .endpointError, reçu \(outcome)"); return
        }
        #expect(Stub.deepLCalls == 0)
    }

    /// Sans serveur local réglé, le secours part directement — un utilisateur
    /// qui n'a jamais installé Ollama reste servi.
    @Test func withoutAnyLocalServerTheFallbackGoesFirst() async {
        Stub.reset()
        Stub.deepLReply = deepL("Salut <x>{{Name}}</x> !")
        let outcome = await TranslationEngine.translate(
            request, localBaseURL: nil, localSession: session(),
            fallback: key, fallbackSession: session())
        #expect(outcome == .translated("Salut {{Name}} !", by: .fallback))
    }

    /// Ni local ni secours : le dire, plutôt que de rendre une traduction vide.
    @Test func withNeitherEngineTheCallIsAnError() async {
        Stub.reset()
        let outcome = await TranslationEngine.translate(
            request, localBaseURL: nil, localSession: session(),
            fallback: nil, fallbackSession: session())
        guard case .endpointError = outcome else {
            Issue.record("attendu .endpointError, reçu \(outcome)"); return
        }
        #expect(Stub.deepLCalls == 0)
    }

    /// Le gate de marques vaut pour DeepL comme pour le reste : une marque
    /// dure perdue est un refus, pas une traduction.
    @Test func aFallbackAnswerMissingAHardMarkerIsRefused() async {
        Stub.reset()
        Stub.localReply = localCompletion("Salut !")
        Stub.deepLReply = deepL("Salut !")
        let outcome = await TranslationEngine.translate(
            request, localBaseURL: local, localSession: session(),
            fallback: key, fallbackSession: session())
        #expect(outcome == .refusedTokens(missing: ["{{Name}}"]))
    }

    /// Une marque dure **dupliquée** est une divergence, pas un détail : le
    /// chemin d'écriture la refuse, et le moteur doit la refuser pareil —
    /// sinon la clé finit dans les erreurs plutôt que dans la liste de ce
    /// qu'il reste à traduire à la main.
    @Test func aFallbackAnswerDoublingAHardMarkerIsRefused() async {
        Stub.reset()
        Stub.localReply = localCompletion("Salut !")
        Stub.deepLReply = deepL("Salut <x>{{Name}}</x> et <x>{{Name}}</x> !")
        let outcome = await TranslationEngine.translate(
            request, localBaseURL: local, localSession: session(),
            fallback: key, fallbackSession: session())
        #expect(outcome == .refusedTokens(missing: ["{{Name}}"]))
    }

    /// Une clé refusée coupe le secours pour tout le lot : c'est la panne que
    /// retenter à chaque clé ne peut pas réparer.
    @Test func aRefusedKeyStopsTheFallback() async {
        Stub.reset()
        Stub.deepLReply = ""
        Stub.deepLStatus = 403
        let outcome = await TranslationEngine.translate(
            request, localBaseURL: local, localSession: session(),
            fallback: key, fallbackSession: session())
        #expect(outcome == .fallbackUnauthorized)
        #expect(Stub.deepLCalls == 1)
    }

    @Test func quotaExhaustedIsReportedAsSuch() async {
        Stub.reset()
        Stub.deepLReply = ""
        Stub.deepLStatus = 456
        let outcome = await TranslationEngine.translate(
            request, localBaseURL: local, localSession: session(),
            fallback: key, fallbackSession: session())
        #expect(outcome == .quotaExhausted)
    }

    /// Le rythme refusé deux fois remonte sous son propre nom : l'appelant
    /// coupe le secours comme pour un quota, mais ne dira pas à l'utilisateur
    /// qu'il a épuisé un quota auquel il n'a pas touché.
    @Test func aRefusedRateIsReportedUnderItsOwnName() async {
        Stub.reset()
        Stub.deepLReply = ""
        Stub.deepLStatus = 429
        let outcome = await TranslationEngine.translate(
            request, localBaseURL: local, localSession: session(),
            fallback: key, fallbackSession: session(), fallbackRetryDelay: .zero)
        #expect(outcome == .fallbackRateLimited)
        #expect(Stub.deepLCalls == 2)   // l'unique retry, et pas un de plus
    }
}
