import Foundation

/// Ce qu'Ollama sait dire d'un modèle **avant** qu'on s'en serve.
///
/// Un modèle à *raisonnement* produit une chaîne de pensée avant sa réponse.
/// Pour un chat c'est une qualité ; ici c'est rédhibitoire : le raisonnement
/// épuise le `max_tokens` de `LocalLLMClient`, qui rejette alors la réponse
/// pour `finish_reason=length`. Mesuré le 2026-08-20 sur un M1 Pro 16 Go,
/// `qwen3.5:9b` mettait **plus de 300 secondes** à répondre « Bonjour ».
/// Le découvrir sur un lot de 500 clés coûte une soirée ; le lire ici coûte
/// une requête locale.
///
/// La route est **native à Ollama** (`POST /api/show`), hors du dialecte
/// compatible OpenAI que parle le reste du client. LM Studio ne la connaît
/// pas et répond 404 : ce n'est pas une erreur à montrer, c'est une
/// information qu'on n'a pas — d'où `nil` partout plutôt qu'un jeté.
public enum OllamaCapabilities {

    public struct Report: Equatable, Sendable {
        public let capabilities: [String]

        public init(capabilities: [String]) {
            self.capabilities = capabilities
        }

        /// Le modèle délibère avant de répondre.
        public var thinks: Bool { capabilities.contains("thinking") }
        /// Le modèle accepte des images — inutile ici, et plus lourd à
        /// paramètres égaux, mais pas disqualifiant.
        public var sees: Bool { capabilities.contains("vision") }

        /// Seul le raisonnement casse le client : la vision ne fait que
        /// coûter, elle laisse le modèle répondre.
        public var isSuitableForTranslation: Bool { !thinks }
    }

    public static func fetch(model: String, baseURL: URL,
                             session: URLSession) async -> Report? {
        guard !model.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var request = URLRequest(url: nativeRoot(of: baseURL)
            .appendingPathComponent("api/show"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model])
        guard request.httpBody != nil else { return nil }

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let capabilities = json["capabilities"] as? [String] else { return nil }
        return Report(capabilities: capabilities)
    }

    /// L'API native vit à la racine du serveur. Une URL réglée sur `…/v1` —
    /// la forme que LM Studio annonce, et qu'Ollama accepte aussi — donnerait
    /// sinon `/v1/api/show`. Même leçon que le séparateur doublé du client.
    private static func nativeRoot(of base: URL) -> URL {
        var text = base.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix("/v1") { text.removeLast(3) }
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text) ?? base
    }
}
