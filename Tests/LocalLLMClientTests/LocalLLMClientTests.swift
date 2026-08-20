import Foundation
import Testing
@testable import StarHubTHCore

/// Tâche 12 du plan P2b — le client LLM local : completion, prompt gardé,
/// retry unique sur marques dures. Zéro vrai réseau : tout passe par un
/// stub `URLProtocol` à routeur. Sérielle : le stub vit dans des statics.
@Suite(.serialized)
struct LocalLLMClientTests {

    // MARK: - Stub

    private enum Reply {
        case json(String)
        case raw(Data, status: Int = 200)
        case status(Int)
        case fail
    }

    private final class LLMStub: URLProtocol {
        nonisolated(unsafe) static var router: (URLRequest) -> Reply = { _ in .fail }
        nonisolated(unsafe) static var seenBodies: [Data] = []
        nonisolated(unsafe) static var seenURLs: [URL] = []
        nonisolated(unsafe) static var calls = 0

        static func route(_ router: @escaping (URLRequest) -> Reply) {
            self.router = router
            seenBodies = []
            seenURLs = []
            calls = 0
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.calls += 1
            Self.seenURLs.append(request.url!)
            Self.seenBodies.append(Self.body(of: request))
            switch Self.router(request) {
            case .json(let text):
                deliver(status: 200, payload: Data(text.utf8))
            case .raw(let data, let status):
                deliver(status: status, payload: data)
            case .status(let status):
                deliver(status: status, payload: Data())
            case .fail:
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            }
        }

        private func deliver(status: Int, payload: Data) {
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: payload)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

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

    private func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LLMStub.self]
        return URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }

    private func decodedBody(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let base = URL(string: "http://127.0.0.1:11434")!

    private func request(source: String,
                         glossary: [GlossaryEntry] = [],
                         sectionLabel: String? = nil) -> LocalLLMClient.Request {
        .init(model: "qwen2.5", source: source,
              glossary: glossary, sectionLabel: sectionLabel)
    }

    private static func completion(_ content: String,
                                   finish: String = "stop",
                                   toolCalls: String? = nil) -> String {
        var message = #""role":"assistant","content":"\#(content)""#
        if let toolCalls {
            message += #","tool_calls":\#(toolCalls)"#
        }
        return #"{"choices":[{"finish_reason":"\#(finish)","message":{\#(message)}}]}"#
    }

    // MARK: - systemPrompt

    @Test func systemPromptListsGlossaryInOrderAndWarnsAboutSection() throws {
        let prompt = LocalLLMClient.systemPrompt(for: request(
            source: "Hello",
            glossary: [.init(en: "Iridium Ore", fr: "Minerai d'iridium", kind: .item),
                       .init(en: "Pumpkin", fr: "Citrouille", kind: .item)],
            sectionLabel: "quests"))
        #expect(prompt.contains("- Iridium Ore -> Minerai d'iridium"))
        #expect(prompt.contains("- Pumpkin -> Citrouille"))
        let iridium = try #require(prompt.range(of: "- Iridium Ore"))
        let pumpkin = try #require(prompt.range(of: "- Pumpkin"))
        #expect(iridium.lowerBound < pumpkin.lowerBound)   // l'ordre des entrées est gardé
        #expect(prompt.contains("Section label (unreliable, context only): quests"))
        #expect(prompt.contains("Preserve every game marker EXACTLY"))
    }

    @Test func systemPromptOmitsGlossaryAndSectionWhenAbsent() {
        let prompt = LocalLLMClient.systemPrompt(for: request(source: "Hello"))
        #expect(!prompt.contains(" -> "))
        #expect(!prompt.contains("Section label"))
    }

    // MARK: - listModels

    @Test func listModelsExtractsIDsInOrder() async throws {
        LLMStub.route { _ in .json(#"{"data":[{"id":"qwen2.5"},{"id":"gemma2"},{"other":1}]}"#) }
        let models = try await LocalLLMClient.listModels(baseURL: base, session: stubbedSession())
        #expect(models == ["qwen2.5", "gemma2"])
    }

    @Test func listModelsDegradesEmptyAndGarbageToEmptyList() async throws {
        LLMStub.route { _ in .raw(Data()) }
        #expect(try await LocalLLMClient.listModels(baseURL: base, session: stubbedSession()) == [])

        LLMStub.route { _ in .json("not json at all") }
        #expect(try await LocalLLMClient.listModels(baseURL: base, session: stubbedSession()) == [])
    }

    @Test func listModelsRejectsNon200ByThrowing() async {
        LLMStub.route { _ in .status(404) }
        await #expect(throws: URLError.self) {
            _ = try await LocalLLMClient.listModels(baseURL: base, session: stubbedSession())
        }
    }

    // MARK: - probeBricks

    @Test func probeBricksReportsOnlyAnsweringBricks() async {
        LLMStub.route { request in
            request.url?.port == 11434
                ? .json(#"{"data":[{"id":"qwen2.5"},{"id":"gemma2"}]}"#)
                : .fail
        }
        let results = await LocalLLMClient.probeBricks(session: stubbedSession())
        #expect(results.count == 1)
        #expect(results.first?.baseURL.port == 11434)
        #expect(results.first?.models == ["qwen2.5", "gemma2"])
    }

    // MARK: - translate : réponses rejetées

    @Test func translateReturnsContentOnCleanStop() async {
        LLMStub.route { _ in .json(Self.completion("Bonjour le monde")) }
        let outcome = await LocalLLMClient.translate(request(source: "Hello world"),
                                                     baseURL: base, session: stubbedSession())
        #expect(outcome == .translated("Bonjour le monde"))
    }

    @Test func translateRejectsTruncatedFinishReason() async {
        LLMStub.route { _ in .json(Self.completion("Bonjour tronqué", finish: "length")) }
        let outcome = await LocalLLMClient.translate(request(source: "Hello world"),
                                                     baseURL: base, session: stubbedSession())
        guard case .endpointError = outcome else {
            Issue.record("attendu endpointError, eu \(outcome)")
            return
        }
        #expect(LLMStub.calls == 1)   // pas de retry hors marques dures
    }

    @Test func translateRejectsToolCallsAsRefusal() async {
        LLMStub.route { _ in .json(Self.completion("", toolCalls: #"[{"id":"t1"}]"#)) }
        let outcome = await LocalLLMClient.translate(request(source: "Hello world"),
                                                     baseURL: base, session: stubbedSession())
        #expect(outcome == .refusedTokens(missing: []))
    }

    @Test func translateRejectsEmptyContentAsRefusal() async {
        LLMStub.route { _ in .json(Self.completion("")) }
        let outcome = await LocalLLMClient.translate(request(source: "Hello world"),
                                                     baseURL: base, session: stubbedSession())
        #expect(outcome == .refusedTokens(missing: []))
    }

    @Test func translateReportsTransportFailureAsEndpointError() async {
        LLMStub.route { _ in .fail }
        let outcome = await LocalLLMClient.translate(request(source: "Hello world"),
                                                     baseURL: base, session: stubbedSession())
        guard case .endpointError = outcome else {
            Issue.record("attendu endpointError, eu \(outcome)")
            return
        }
    }

    @Test func translateRejectsNon200AsEndpointError() async {
        LLMStub.route { _ in .status(500) }
        let outcome = await LocalLLMClient.translate(request(source: "Hello world"),
                                                     baseURL: base, session: stubbedSession())
        guard case .endpointError = outcome else {
            Issue.record("attendu endpointError, eu \(outcome)")
            return
        }
    }

    @Test func translateRejectsOversizedResponse() async {
        LLMStub.route { _ in .raw(Data(repeating: 0x61, count: LocalLLMEndpoint.maxResponseBytes + 1)) }
        let outcome = await LocalLLMClient.translate(request(source: "Hello world"),
                                                     baseURL: base, session: stubbedSession())
        guard case .endpointError = outcome else {
            Issue.record("attendu endpointError, eu \(outcome)")
            return
        }
    }

    // MARK: - translate : retry sur marques dures

    @Test func retryRecoversMissingHardToken() async {
        // 1ʳᵉ réponse : le $b a disparu. 2ᵉ : il est là.
        LLMStub.route { _ in
            LLMStub.calls == 1
                ? .json(Self.completion("Bonjour le monde brillant"))
                : .json(Self.completion("Bonjour$b le monde brillant"))
        }
        let outcome = await LocalLLMClient.translate(request(source: "Hello$b bright world"),
                                                     baseURL: base, session: stubbedSession())
        #expect(outcome == .translated("Bonjour$b le monde brillant"))
        #expect(LLMStub.calls == 2)
    }

    @Test func retryNamesTheMissingMarkersInThePrompt() async throws {
        LLMStub.route { _ in
            LLMStub.calls == 1
                ? .json(Self.completion("Bonjour le monde"))
                : .json(Self.completion("Bonjour$b le monde"))
        }
        _ = await LocalLLMClient.translate(request(source: "Hello$b world"),
                                           baseURL: base, session: stubbedSession())
        #expect(LLMStub.seenBodies.count == 2)
        let retryBody = try decodedBody(try #require(LLMStub.seenBodies.last))
        let messages = try #require(retryBody["messages"] as? [[String: Any]])
        let system = try #require(messages.first?["content"] as? String)
        #expect(system.contains("$b"), "le prompt du retry nomme la marque manquante")
    }

    @Test func bothAttemptsMissingTokenRefusesWithTheTokenNamed() async {
        LLMStub.route { _ in .json(Self.completion("Bonjour le monde")) }
        let outcome = await LocalLLMClient.translate(request(source: "Hello$b world"),
                                                     baseURL: base, session: stubbedSession())
        #expect(outcome == .refusedTokens(missing: ["$b"]))
        #expect(LLMStub.calls == 2)   // l'unique retry a eu lieu
    }

    @Test func noRetryWhenNoHardTokenMissing() async {
        LLMStub.route { _ in .json(Self.completion("Bonjour le monde")) }
        _ = await LocalLLMClient.translate(request(source: "Hello world"),
                                           baseURL: base, session: stubbedSession())
        #expect(LLMStub.calls == 1)
    }

    @Test func bestOfTwoPrefersFewerMissingTokens() async {
        // 1ᵉʳ essai : deux marques manquantes ({{Gender}} et $b). Retry : une
        // seule ($b). Le retry gagne ; encore incomplet → refus nommé sur les
        // manquantes du MEILLEUR.
        LLMStub.route { _ in
            LLMStub.calls == 1
                ? .json(Self.completion("Réponse sans aucune marque"))
                : .json(Self.completion("Réponse avec {{Gender}} dedans"))
        }
        let outcome = await LocalLLMClient.translate(
            request(source: "Use {{Gender}} and $b here"),
            baseURL: base, session: stubbedSession())
        #expect(outcome == .refusedTokens(missing: ["$b"]))
    }

    // MARK: - Corps de requête

    @Test func requestBodyIsLocked() async throws {
        LLMStub.route { _ in .json(Self.completion("Bonjour")) }
        let source = "A rather long sentence to translate today"
        _ = await LocalLLMClient.translate(request(source: source),
                                           baseURL: base, session: stubbedSession())
        let body = try decodedBody(try #require(LLMStub.seenBodies.first))
        #expect(body["model"] as? String == "qwen2.5")
        #expect(body["stream"] as? Bool == false)
        #expect(body["temperature"] as? Double == 0.2)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages.first?["role"] as? String == "system")
        #expect(messages.last?["role"] as? String == "user")
        #expect(messages.last?["content"] as? String == source)   // la source seule
    }

    @Test func maxTokensIsClamped() async throws {
        LLMStub.route { _ in .json(Self.completion("ok")) }
        _ = await LocalLLMClient.translate(request(source: "Short"),   // 2×5=10 → 64
                                           baseURL: base, session: stubbedSession())
        let first = try decodedBody(try #require(LLMStub.seenBodies.first))
        #expect(first["max_tokens"] as? Int == 64)

        LLMStub.route { _ in .json(Self.completion("ok")) }
        let long = String(repeating: "a", count: 1000)   // 2×1000 → 1024
        _ = await LocalLLMClient.translate(request(source: long),
                                           baseURL: base, session: stubbedSession())
        let second = try decodedBody(try #require(LLMStub.seenBodies.first))
        #expect(second["max_tokens"] as? Int == 1024)
    }

    @Test func stopOnlyForSingleLineSources() async throws {
        LLMStub.route { _ in .json(Self.completion("ok")) }
        _ = await LocalLLMClient.translate(request(source: "One line only"),
                                           baseURL: base, session: stubbedSession())
        let single = try decodedBody(try #require(LLMStub.seenBodies.first))
        #expect(single["stop"] as? [String] == ["\n"])

        LLMStub.route { _ in .json(Self.completion("ok")) }
        _ = await LocalLLMClient.translate(request(source: "Line one\nLine two"),
                                           baseURL: base, session: stubbedSession())
        let multi = try decodedBody(try #require(LLMStub.seenBodies.first))
        #expect(multi["stop"] == nil)
    }

    @Test func postsToChatCompletionsAndHonoursV1Base() async throws {
        LLMStub.route { _ in .json(Self.completion("ok")) }
        _ = await LocalLLMClient.translate(request(source: "Hello"),
                                           baseURL: base, session: stubbedSession())
        #expect(try #require(LLMStub.seenURLs.first).absoluteString
                == "http://127.0.0.1:11434/v1/chat/completions")

        LLMStub.route { _ in .json(Self.completion("ok")) }
        let withV1 = URL(string: "http://127.0.0.1:1234/v1")!
        _ = await LocalLLMClient.translate(request(source: "Hello"),
                                           baseURL: withV1, session: stubbedSession())
        #expect(try #require(LLMStub.seenURLs.first).absoluteString
                == "http://127.0.0.1:1234/v1/chat/completions")   // pas de /v1/v1
    }

    /// Un copier-coller depuis la barre d'adresse d'un navigateur porte un
    /// slash final. Concaténé tel quel, il donnait `//v1/chat/completions` :
    /// le serveur répond alors 301 pour normaliser, la redirection est
    /// refusée par sécurité, et **toutes** les clés du lot échouent en
    /// « HTTP 301 » sur une URL que le bouton Tester venait d'accepter.
    @Test func aTrailingSlashInTheBaseUrlDoesNotDoubleTheSeparator() async throws {
        LLMStub.route { _ in .json(Self.completion("ok")) }
        _ = await LocalLLMClient.translate(
            request(source: "Hello"),
            baseURL: URL(string: "http://127.0.0.1:11434/")!, session: stubbedSession())
        #expect(try #require(LLMStub.seenURLs.first).absoluteString
                == "http://127.0.0.1:11434/v1/chat/completions")

        LLMStub.route { _ in .json(Self.completion("ok")) }
        _ = await LocalLLMClient.translate(
            request(source: "Hello"),
            baseURL: URL(string: "http://127.0.0.1:1234/v1/")!, session: stubbedSession())
        #expect(try #require(LLMStub.seenURLs.first).absoluteString
                == "http://127.0.0.1:1234/v1/chat/completions")
    }

    /// Le même slash final sur la liste des modèles — c'est ce chemin que le
    /// bouton « Tester » emprunte, celui qui déclarait l'URL bonne.
    @Test func listModelsAlsoSurvivesATrailingSlash() async throws {
        LLMStub.route { _ in .json(#"{"data":[{"id":"mistral"}]}"#) }
        _ = try await LocalLLMClient.listModels(
            baseURL: URL(string: "http://127.0.0.1:11434/")!, session: stubbedSession())
        #expect(try #require(LLMStub.seenURLs.first).absoluteString
                == "http://127.0.0.1:11434/v1/models")
    }
}
