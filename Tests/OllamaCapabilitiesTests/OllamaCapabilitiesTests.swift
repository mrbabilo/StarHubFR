import Foundation
import Testing
@testable import StarHubTHCore

/// Ce qu'Ollama dit d'un modèle avant qu'on s'en serve. Un modèle à
/// raisonnement délibère avant de répondre : il épuise le budget de jetons du
/// client, qui rejette alors la réponse — chaque clé échoue. Le savoir avant
/// vaut mieux que le découvrir sur un lot de 500 clés.
@Suite(.serialized)
struct OllamaCapabilitiesTests {

    private final class Stub: URLProtocol {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var payload = ""
        nonisolated(unsafe) static var fails = false
        nonisolated(unsafe) static var seenURLs: [URL] = []
        nonisolated(unsafe) static var seenBodies: [Data] = []

        static func reply(_ json: String, status: Int = 200, fails: Bool = false) {
            self.status = status
            payload = json
            self.fails = fails
            seenURLs = []
            seenBodies = []
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
        override func stopLoading() {}

        override func startLoading() {
            Self.seenURLs.append(request.url!)
            if let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    data.append(buffer, count: read)
                }
                stream.close()
                Self.seenBodies.append(data)
            } else {
                Self.seenBodies.append(request.httpBody ?? Data())
            }
            guard !Self.fails else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(Self.payload.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return URLSession(configuration: config)
    }

    private let base = URL(string: "http://127.0.0.1:11434")!

    /// La réponse réelle d'Ollama pour `qwen3.5:9b`, relevée le 2026-08-20.
    @Test func aReasoningModelIsReportedAsSuch() async {
        Stub.reply(#"{"capabilities":["completion","vision","tools","thinking"]}"#)
        let report = await OllamaCapabilities.fetch(model: "qwen3.5:9b",
                                                    baseURL: base, session: session())
        #expect(report?.thinks == true)
        #expect(report?.sees == true)
        #expect(report?.isSuitableForTranslation == false)
    }

    @Test func aPlainInstructModelIsSuitable() async {
        Stub.reply(#"{"capabilities":["completion","tools"]}"#)
        let report = await OllamaCapabilities.fetch(model: "qwen2.5:7b",
                                                    baseURL: base, session: session())
        #expect(report?.thinks == false)
        #expect(report?.isSuitableForTranslation == true)
    }

    /// La vision seule n'est pas rédhibitoire : elle alourdit, elle n'empêche
    /// pas de répondre. Seul le raisonnement casse le client.
    @Test func visionAloneDoesNotDisqualify() async {
        Stub.reply(#"{"capabilities":["completion","vision"]}"#)
        let report = await OllamaCapabilities.fetch(model: "m", baseURL: base,
                                                    session: session())
        #expect(report?.sees == true)
        #expect(report?.isSuitableForTranslation == true)
    }

    @Test func theRequestNamesTheModelOnTheNativePath() async {
        Stub.reply(#"{"capabilities":["completion"]}"#)
        _ = await OllamaCapabilities.fetch(model: "qwen2.5:7b", baseURL: base,
                                           session: session())
        #expect(Stub.seenURLs.first?.absoluteString == "http://127.0.0.1:11434/api/show")
        let body = String(decoding: Stub.seenBodies.first ?? Data(), as: UTF8.self)
        #expect(body.contains("qwen2.5:7b"))
    }

    /// L'API native vit à la racine : une URL réglée sur `…/v1` — la forme que
    /// LM Studio annonce et qu'Ollama accepte aussi — ne doit pas produire
    /// `/v1/api/show`.
    @Test func aV1SuffixIsStrippedBeforeTheNativePath() async {
        Stub.reply(#"{"capabilities":["completion"]}"#)
        _ = await OllamaCapabilities.fetch(
            model: "m", baseURL: URL(string: "http://127.0.0.1:1234/v1/")!,
            session: session())
        #expect(Stub.seenURLs.first?.absoluteString == "http://127.0.0.1:1234/api/show")
    }

    /// LM Studio ne connaît pas cette route : 404. Ce n'est pas une erreur à
    /// montrer, c'est une information qu'on n'a pas.
    @Test func aServerWithoutThatRouteReportsNothing() async {
        Stub.reply("", status: 404)
        #expect(await OllamaCapabilities.fetch(model: "m", baseURL: base,
                                               session: session()) == nil)
    }

    @Test func anUnreadableAnswerReportsNothing() async {
        Stub.reply("pas du json")
        #expect(await OllamaCapabilities.fetch(model: "m", baseURL: base,
                                               session: session()) == nil)
    }

    @Test func anUnreachableServerReportsNothing() async {
        Stub.reply("", fails: true)
        #expect(await OllamaCapabilities.fetch(model: "m", baseURL: base,
                                               session: session()) == nil)
    }

    @Test func anEmptyModelNameIsNotEvenAsked() async {
        Stub.reply(#"{"capabilities":["completion"]}"#)
        #expect(await OllamaCapabilities.fetch(model: "", baseURL: base,
                                               session: session()) == nil)
        #expect(Stub.seenURLs.isEmpty)
    }
}
