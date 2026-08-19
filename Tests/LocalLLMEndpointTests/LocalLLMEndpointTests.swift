import Foundation
import Testing
@testable import StarHubTHCore

/// Tâche 11 du plan P2b — l'endpoint IA locale : loopback uniquement,
/// aucune dépendance réseau imprévue (spec §6). Rien d'autre ne doit
/// pouvoir être validé : le prompt du hub contient le texte des mods.
struct LocalLLMEndpointTests {

    // MARK: - Acceptations

    @Test func acceptsPlainLocalhost() {
        #expect(LocalLLMEndpoint.validate("http://localhost:11434") != nil)
    }

    @Test func acceptsLoopbackIPv4Range() {
        #expect(LocalLLMEndpoint.validate("http://127.0.0.1:1234/v1") != nil)
        #expect(LocalLLMEndpoint.validate("http://127.200.1.9") != nil)   // tout 127/8
    }

    @Test func acceptsIPv6Loopback() {
        #expect(LocalLLMEndpoint.validate("http://[::1]:11434") != nil)
    }

    // MARK: - Refus — la matrice de la référence

    @Test func refusesHTTPS() {
        #expect(LocalLLMEndpoint.validate("https://localhost:11434") == nil)
    }

    @Test func refusesEvilSubdomainOfLocalhost() {
        #expect(LocalLLMEndpoint.validate("http://localhost.evil.com") == nil)
    }

    @Test func refusesDNSRebindingHosts() {
        #expect(LocalLLMEndpoint.validate("http://127.0.0.1.nip.io") == nil)
        #expect(LocalLLMEndpoint.validate("http://localhost.nip.io") == nil)
    }

    @Test func refusesPrivateAndPublicRanges() {
        #expect(LocalLLMEndpoint.validate("http://10.0.0.1") == nil)
        #expect(LocalLLMEndpoint.validate("http://192.168.1.5") == nil)
        #expect(LocalLLMEndpoint.validate("http://172.16.0.1") == nil)
        #expect(LocalLLMEndpoint.validate("http://example.com") == nil)
    }

    @Test func refusesGarbageAndEmpty() {
        #expect(LocalLLMEndpoint.validate("") == nil)
        #expect(LocalLLMEndpoint.validate("pas une url") == nil)
        #expect(LocalLLMEndpoint.validate("http://") == nil)
    }

    // MARK: - Constante

    @Test func maxResponseBytesIsFourMiB() {
        #expect(LocalLLMEndpoint.maxResponseBytes == 4 * 1024 * 1024)
    }

    // MARK: - Session : les redirections sont annulées, pas suivies

    /// Répond 302 vers un hôte externe. Si la session suivait la
    /// redirection, le stub l'attraperait à nouveau (`hits == 2`) — le
    /// compte prouve qu'aucune seconde requête n'a été émise.
    private final class RedirectStub: URLProtocol {
        nonisolated(unsafe) static var hits = 0

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.hits += 1
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
                headerFields: ["Location": "http://example.com/evil"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    @Test func sessionNeverFollowsRedirects() async throws {
        RedirectStub.hits = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RedirectStub.self]
        let session = LocalLLMEndpoint.makeSession(configuration: config, timeout: 5)
        defer { session.finishTasksAndInvalidate() }

        // Pas d'erreur transport : c'est la réponse 3xx d'origine qui est
        // rendue, jamais le contenu de la cible — et une seule requête émise.
        let request = URLRequest(url: URL(string: "http://127.0.0.1:1/models")!)
        let (data, response) = try await session.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 302)   // le 302 lui-même, pas la suite
        #expect(data.isEmpty)
        #expect(RedirectStub.hits == 1, "aucune seconde requête vers la cible")
    }
}
