import Foundation

/// Tâche 12 du plan P2b — le client LLM local (spec §6).
///
/// Endpoint OpenAI-compatible (`POST {base}/v1/chat/completions`), prompt
/// système anglais gardé au mot près, réponses rejetées selon des critères
/// explicites, **un seul retry** sur marques dures manquantes. Les marques
/// ne sont jamais réinsérées programmatiquement : préservation
/// instructionnelle, vérification a posteriori par le même gate que la
/// saisie manuelle (`TranslationTokenCheck`).
public enum LocalLLMClient {

    public struct ProbeResult: Equatable, Sendable {
        public let baseURL: URL
        public let models: [String]

        public init(baseURL: URL, models: [String]) {
            self.baseURL = baseURL
            self.models = models
        }
    }

    /// Les deux briques connues : Ollama (11434) et LM Studio (1234).
    public static let knownBricks: [URL] = [
        URL(string: "http://127.0.0.1:11434")!,
        URL(string: "http://127.0.0.1:1234")!,
    ]

    /// Sondage parallèle des briques connues — ne répond que celles qui ont
    /// un `/v1/models` valide. Le timeout (2 s en production) vient de la
    /// session passée par l'appelant.
    public static func probeBricks(session: URLSession) async -> [ProbeResult] {
        await withTaskGroup(of: ProbeResult?.self) { group in
            for base in knownBricks {
                group.addTask {
                    guard let models = try? await listModels(baseURL: base, session: session) else {
                        return nil
                    }
                    return ProbeResult(baseURL: base, models: models)
                }
            }
            var out: [ProbeResult] = []
            for await result in group where result != nil {
                out.append(result!)
            }
            return out.sorted { ($0.baseURL.port ?? 0) < ($1.baseURL.port ?? 0) }
        }
    }

    /// `GET {base}/v1/models`. Corps vide ou illisible → `[]` (le serveur
    /// répond mais n'est pas un endpoint de modèles exploitable) ; une
    /// erreur transport ou un statut non-200 jette — c'est ce qui distingue
    /// « brique absente » de « brique présente » dans `probeBricks`.
    public static func listModels(baseURL: URL, session: URLSession) async throws -> [String] {
        let (data, response) = try await session.data(for: URLRequest(url: api(baseURL, "/models")))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard data.count <= LocalLLMEndpoint.maxResponseBytes,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["id"] as? String }
    }

    public struct Request: Sendable {
        public let model: String
        public let source: String
        /// Les entrées glossaire **déjà matchées** pour cette source (≤ 15) —
        /// le matching n'est pas refait ici.
        public let glossary: [GlossaryEntry]
        public let sectionLabel: String?

        public init(model: String, source: String,
                    glossary: [GlossaryEntry], sectionLabel: String?) {
            self.model = model
            self.source = source
            self.glossary = glossary
            self.sectionLabel = sectionLabel
        }
    }

    public enum Outcome: Equatable, Sendable {
        case translated(String)
        case refusedTokens(missing: [String])   // après l'unique retry
        case endpointError(String)
    }

    public static func translate(_ request: Request, baseURL: URL,
                                 session: URLSession) async -> Outcome {
        let first = await fetch(request, retryMissing: nil, baseURL: baseURL, session: session)
        guard case .content(let text) = first else { return first.outcome }
        let missing = hardMissing(source: request.source, target: text)
        guard !missing.isEmpty else { return .translated(text) }

        // L'unique retry, uniquement sur marques dures manquantes.
        let second = await fetch(request, retryMissing: missing, baseURL: baseURL, session: session)
        guard case .content(let retryText) = second else { return .refusedTokens(missing: missing) }
        let retryMissingTokens = hardMissing(source: request.source, target: retryText)
        // Le meilleur des deux : le moins de manquantes ; à égalité, le premier.
        if retryMissingTokens.count < missing.count {
            return retryMissingTokens.isEmpty
                ? .translated(retryText)
                : .refusedTokens(missing: retryMissingTokens)
        }
        return .refusedTokens(missing: missing)
    }

    /// Le prompt système, déterministe — le texte anglais verrouillé par la
    /// spec §6, puis les termes imposés et l'étiquette de section.
    public static func systemPrompt(for request: Request) -> String {
        systemPrompt(for: request, retryMissing: nil)
    }

    private static func systemPrompt(for request: Request, retryMissing: [String]?) -> String {
        var prompt = """
        You are a translator for Stardew Valley mods. Output ONLY the French \
        translation of the given text — no explanation, no quotes, no commentary. \
        Preserve every game marker EXACTLY, character for character: {{tokens}}, \
        $b, #, ^, @, gender switches, {N} placeholders. Never translate, move, \
        add or drop one. Use the glossary terms exactly as given. French rules: \
        use French punctuation and guillemets where the source uses quotes; keep \
        the register of the source.
        """
        if !request.glossary.isEmpty {
            prompt += "\n" + request.glossary.map { "- \($0.en) -> \($0.fr)" }.joined(separator: "\n")
        }
        if let sectionLabel = request.sectionLabel {
            prompt += "\nSection label (unreliable, context only): \(sectionLabel)"
        }
        if let retryMissing, !retryMissing.isEmpty {
            prompt += "\nThe previous attempt was missing these required markers: "
                + retryMissing.joined(separator: ", ")
                + ". Translate again and include each one exactly, character for character."
        }
        return prompt
    }

    // MARK: - Une requête, ses rejets

    /// Le résultat d'un appel, avant la mécanique de retry.
    private enum Fetch {
        case content(String)
        case rejected          // tool_calls ou contenu vide : le modèle n'a pas joué le jeu
        case failed(String)    // transport, statut, troncature, plafond, JSON cassé

        var outcome: Outcome {
            switch self {
            case .content(let text): .translated(text)
            case .rejected: .refusedTokens(missing: [])
            case .failed(let message): .endpointError(message)
            }
        }
    }

    private static func fetch(_ request: Request, retryMissing: [String]?,
                              baseURL: URL, session: URLSession) async -> Fetch {
        var body: [String: Any] = [
            "model": request.model,
            "messages": [
                ["role": "system",
                 "content": systemPrompt(for: request, retryMissing: retryMissing)],
                ["role": "user", "content": request.source],
            ],
            "stream": false,
            "temperature": 0.2,
            "max_tokens": min(max(2 * request.source.count, 64), 1024),
        ]
        if !request.source.contains("\n") {
            body["stop"] = ["\n"]   // ssi mono-ligne : une réponse multiligne y est suspecte
        }
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            return .failed("requête inencodable")
        }
        var urlRequest = URLRequest(url: api(baseURL, "/chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = payload

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            return .failed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode.description ?? "?"
            return .failed("HTTP \(code)")
        }
        guard data.count <= LocalLLMEndpoint.maxResponseBytes else {
            return .failed("réponse au-delà du plafond de 4 Mio")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first else {
            return .failed("réponse illisible")
        }
        if let finish = choice["finish_reason"] as? String, finish != "stop" {
            return .failed("finish_reason=\(finish)")   // tronquée : le contenu est inutilisable
        }
        guard let message = choice["message"] as? [String: Any] else {
            return .failed("pas de message")
        }
        if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
            return .rejected
        }
        guard let content = message["content"] as? String, !content.isEmpty else {
            return .rejected
        }
        return .content(content)
    }

    /// Les marques dures manquantes entre source et traduction.
    private static func hardMissing(source: String, target: String) -> [String] {
        TranslationTokenCheck.mismatches(source: source, target: target)
            .filter(\.isHard)
            .map(\.token)
    }

    /// `{base}/v1{path}`, sans doubler le `/v1` quand l'URL saisie le porte
    /// déjà (LM Studio s'annonce souvent en `http://localhost:1234/v1`) **ni
    /// le séparateur** quand elle finit par un slash — ce que donne un
    /// copier-coller depuis une barre d'adresse. Concaténé tel quel, ce
    /// slash produisait `//v1/chat/completions` : le serveur répond 301 pour
    /// normaliser, la redirection est refusée par sécurité, et tout le lot
    /// échoue sur une URL que le bouton « Tester » venait d'accepter.
    ///
    /// Repli sur `base` plutôt qu'un `!` : une URL improbable doit échouer en
    /// erreur HTTP nommée, jamais tuer l'application.
    private static func api(_ base: URL, _ path: String) -> URL {
        var text = base.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        if !text.hasSuffix("/v1") { text += "/v1" }
        return URL(string: text + path) ?? base
    }
}
