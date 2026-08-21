import Foundation
import Testing
@testable import StarHubTHCore

struct DeepLCredentialsTests {

    /// Le suffixe `:fx` désigne une clé du plan gratuit — c'est la
    /// documentation de DeepL qui le dit, et c'est ce qui choisit l'hôte.
    @Test func aFreeKeyRoutesToTheFreeHost() {
        let credentials = DeepLClient.Credentials(key: "279a2e9d-1234:fx")
        #expect(credentials?.baseURL.absoluteString == "https://api-free.deepl.com")
        #expect(credentials?.isFreePlan == true)
    }

    @Test func aProKeyRoutesToTheProHost() {
        let credentials = DeepLClient.Credentials(key: "279a2e9d-1234")
        #expect(credentials?.baseURL.absoluteString == "https://api.deepl.com")
        #expect(credentials?.isFreePlan == false)
    }

    /// Un copier-coller traîne des espaces : ils ne doivent ni casser l'hôte
    /// ni voyager dans l'en-tête d'authentification.
    @Test func surroundingWhitespaceIsTrimmed() {
        let credentials = DeepLClient.Credentials(key: "  279a2e9d-1234:fx \n")
        #expect(credentials?.key == "279a2e9d-1234:fx")
        #expect(credentials?.isFreePlan == true)
    }

    @Test func anEmptyKeyIsNoCredentialsAtAll() {
        #expect(DeepLClient.Credentials(key: "") == nil)
        #expect(DeepLClient.Credentials(key: "   ") == nil)
    }
}

// MARK: - Stub réseau

/// Le stub vit dans des `static` : les suites qui s'en servent sont
/// sérialisées, et il n'y en a **qu'une** pour cette raison — deux suites
/// distinctes tourneraient en parallèle et se marcheraient dessus.
private final class DeepLStub: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var statuses: [Int] = []
    nonisolated(unsafe) static var seenURLs: [URL] = []
    nonisolated(unsafe) static var seenHeaders: [[String: String]] = []
    nonisolated(unsafe) static var seenBodies: [Data] = []

    /// Une réponse pour toutes les requêtes. `statuses` permet d'en enchaîner
    /// de différentes — c'est ce qui rend le retry observable.
    static func reply(_ json: String, status: Int = 200, then statuses: [Int] = []) {
        self.status = status
        self.statuses = statuses
        payload = Data(json.utf8)
        seenURLs = []
        seenHeaders = []
        seenBodies = []
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DeepLStub.self]
        return URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.seenURLs.append(request.url!)
        Self.seenHeaders.append(request.allHTTPHeaderFields ?? [:])
        Self.seenBodies.append(Self.body(of: request))
        let status: Int
        if Self.seenURLs.count > 1, Self.seenURLs.count - 2 < Self.statuses.count {
            status = Self.statuses[Self.seenURLs.count - 2]
        } else {
            status = Self.status
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// `data(for:)` transforme `httpBody` en flux : le stub lit le flux.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 16 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Sérialisée : le stub vit dans des `static`.
@Suite(.serialized)
struct DeepLUsageTests {

    private let free = DeepLClient.Credentials(key: "k:fx")!

    @Test func usageReadsTheCountAndTheLimit() async throws {
        DeepLStub.reply(#"{"character_count":12300,"character_limit":500000}"#)
        let usage = try await DeepLClient.usage(credentials: free, session: DeepLStub.session())
        #expect(usage.used == 12300)
        #expect(usage.limit == 500000)
        #expect(usage.remaining == 487700)
    }

    /// Une réponse Pro porte des champs supplémentaires : les ignorer, pas
    /// échouer dessus.
    @Test func aProResponseWithExtraFieldsStillDecodes() async throws {
        DeepLStub.reply(#"""
        {"character_count":1,"character_limit":2,
         "products":[{"product_type":"translate"}],
         "api_key_character_count":1}
        """#)
        let usage = try await DeepLClient.usage(credentials: free, session: DeepLStub.session())
        #expect(usage.used == 1)
    }

    @Test func theRequestGoesToTheUsagePathWithTheAuthHeader() async throws {
        DeepLStub.reply(#"{"character_count":0,"character_limit":1}"#)
        _ = try await DeepLClient.usage(credentials: free, session: DeepLStub.session())
        #expect(DeepLStub.seenURLs.first?.absoluteString == "https://api-free.deepl.com/v2/usage")
        #expect(DeepLStub.seenHeaders.first?["Authorization"] == "DeepL-Auth-Key k:fx")
    }

    @Test func aRefusedKeyIsNamedAsSuch() async {
        DeepLStub.reply("", status: 403)
        await #expect(throws: DeepLClient.UsageError.unauthorized) {
            _ = try await DeepLClient.usage(credentials: free, session: DeepLStub.session())
        }
    }

    @Test func anUnreadableBodyIsAnError() async {
        DeepLStub.reply("pas du json")
        await #expect(throws: DeepLClient.UsageError.malformed) {
            _ = try await DeepLClient.usage(credentials: free, session: DeepLStub.session())
        }
    }
}
