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

/// Même stub, donc même sérialisation : la suite est unique et ses tests
/// s'exécutent l'un après l'autre.
extension DeepLUsageTests {

    private func body(_ text: String) -> String {
        #"{"translations":[{"detected_source_language":"EN","text":"\#(text)"}]}"#
    }

    private func sentPayload(_ index: Int = 0) throws -> [String: Any] {
        let data = try #require(DeepLStub.seenBodies.indices.contains(index)
                                ? DeepLStub.seenBodies[index] : nil)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func aTranslationComesBackUnwrapped() async {
        DeepLStub.reply(body("Salut <x>{{Name}}</x> !"))
        let outcome = await DeepLClient.translate("Hi {{Name}}!", context: nil,
                                                  credentials: free,
                                                  session: DeepLStub.session())
        #expect(outcome == .translated("Salut {{Name}} !"))
    }

    /// Ce qui part est **enveloppé** : c'est cette ligne du corps qui protège
    /// les marques, et rien d'autre.
    @Test func theRequestCarriesWrappedTextAndTheIgnoreTagsSwitches() async throws {
        DeepLStub.reply(body("Salut"))
        _ = await DeepLClient.translate("Hi {{Name}}!", context: nil,
                                        credentials: free, session: DeepLStub.session())
        let sent = try sentPayload()
        #expect(sent["text"] as? [String] == ["Hi <x>{{Name}}</x>!"])
        #expect(sent["tag_handling"] as? String == "xml")
        // Un **tableau**, pas une chaîne : en JSON, DeepL refuse la seconde
        // forme par « Value for 'ignore_tags' not supported. » — mesuré sur
        // l'API réelle le 2026-08-21, après que la chaîne eut fait échouer
        // chaque traduction sans que rien ne le dise.
        #expect(sent["ignore_tags"] as? [String] == ["x"])
        #expect(sent["target_lang"] as? String == "FR")
        #expect(sent["source_lang"] as? String == "EN")
        #expect(sent["split_sentences"] as? String == "nonewlines")
        #expect(DeepLStub.seenURLs.first?.absoluteString
                == "https://api-free.deepl.com/v2/translate")
    }

    /// L'étiquette de section voyage par `context`, que DeepL ne traduit pas.
    @Test func theSectionLabelTravelsAsUntranslatedContext() async throws {
        DeepLStub.reply(body("Salut"))
        _ = await DeepLClient.translate("Hi", context: "Dialogue locationnel",
                                        credentials: free, session: DeepLStub.session())
        #expect(try sentPayload()["context"] as? String == "Dialogue locationnel")
    }

    @Test func quotaExhaustedIsNamed() async {
        DeepLStub.reply("", status: 456)
        let outcome = await DeepLClient.translate("Hi", context: nil,
                                                  credentials: free,
                                                  session: DeepLStub.session())
        #expect(outcome == .quotaExhausted)
        #expect(DeepLStub.seenURLs.count == 1)  // un 456 ne se retente pas
    }

    /// 429 : une seule nouvelle tentative, temporisée. Si elle passe, la
    /// traduction est rendue — c'est tout l'intérêt du retry.
    @Test func aRateLimitIsRetriedOnceAndSucceeds() async {
        DeepLStub.reply(body("Salut"), status: 429, then: [200])
        let outcome = await DeepLClient.translate("Hi", context: nil,
                                                  credentials: free,
                                                  session: DeepLStub.session(),
                                                  retryDelay: .zero)
        #expect(outcome == .translated("Salut"))
        #expect(DeepLStub.seenURLs.count == 2)
    }

    /// Le second 429 arrête tout : marteler une API qui a déjà dit non deux
    /// fois ne la fera pas céder. L'appelant coupe le secours pour le lot.
    @Test func aSecondRateLimitStopsTheFallback() async {
        DeepLStub.reply("", status: 429, then: [429])
        let outcome = await DeepLClient.translate("Hi", context: nil,
                                                  credentials: free,
                                                  session: DeepLStub.session(),
                                                  retryDelay: .zero)
        #expect(outcome == .rateLimited)
        #expect(DeepLStub.seenURLs.count == 2)
    }

    /// Une clé refusée ne se retente pas, et ne se confond pas avec une
    /// réponse illisible : c'est une panne **définitive**, la seule que
    /// retenter à chaque clé d'un lot ne peut pas réparer.
    @Test func aRefusedKeyIsNamedAndNotRetried() async {
        for status in [401, 403] {
            DeepLStub.reply("", status: status)
            let outcome = await DeepLClient.translate("Hi", context: nil,
                                                      credentials: free,
                                                      session: DeepLStub.session())
            #expect(outcome == .unauthorized, "statut \(status)")
            #expect(DeepLStub.seenURLs.count == 1)
        }
    }

    /// Le message d'erreur ne doit **jamais** porter la clé.
    @Test func noErrorMessageEverCarriesTheKey() async {
        DeepLStub.reply("", status: 500)
        let outcome = await DeepLClient.translate("Hi", context: nil,
                                                  credentials: free,
                                                  session: DeepLStub.session())
        #expect(!"\(outcome)".contains("k:fx"))
    }

    /// Ce que le service **dit** de son refus voyage jusqu'à l'appelant : un
    /// « HTTP 400 » nu a masqué pendant une journée un paramètre mal formé
    /// que la réponse nommait en toutes lettres.
    @Test func theServiceOwnRefusalMessageIsCarried() async {
        DeepLStub.reply(#"{"message":"Value for 'ignore_tags' not supported."}"#, status: 400)
        let outcome = await DeepLClient.translate("Hi", context: nil,
                                                  credentials: free,
                                                  session: DeepLStub.session())
        #expect(outcome == .rejected("HTTP 400 : Value for 'ignore_tags' not supported."))
    }

    /// Une réponse d'erreur sans message reste nommée par son statut.
    @Test func aRefusalWithoutAMessageKeepsItsStatus() async {
        DeepLStub.reply("", status: 400)
        let outcome = await DeepLClient.translate("Hi", context: nil,
                                                  credentials: free,
                                                  session: DeepLStub.session())
        #expect(outcome == .rejected("HTTP 400"))
    }

    @Test func anEmptyTranslationListIsRejected() async {
        DeepLStub.reply(#"{"translations":[]}"#)
        let outcome = await DeepLClient.translate("Hi", context: nil,
                                                  credentials: free,
                                                  session: DeepLStub.session())
        guard case .rejected = outcome else {
            Issue.record("attendu .rejected, reçu \(outcome)"); return
        }
    }
}
