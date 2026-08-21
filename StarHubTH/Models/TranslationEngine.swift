import Foundation

/// L'ordre des tentatives : le local d'abord, toujours ; le secours en ligne
/// seulement s'il a échoué, et seulement s'il est autorisé.
///
/// `LocalLLMClient` n'est pas modifié — il ne sait rien du secours, et c'est
/// bien ainsi : un seul endroit décide.
public enum TranslationEngine {

    public enum Source: Equatable, Sendable { case local, fallback }

    public enum Outcome: Equatable, Sendable {
        case translated(String, by: Source)
        case refusedTokens(missing: [String])
        case endpointError(String)
        /// Le quota du mois est épuisé chez le service de secours.
        case quotaExhausted
        /// Le service de secours a refusé le rythme deux fois de suite.
        /// L'appelant le coupe comme pour un quota — mais rien n'a été
        /// consommé, et l'utilisateur mérite de l'entendre dire autrement.
        case fallbackRateLimited
        /// La clé du service de secours est refusée. Coupe pareil, et se
        /// répare ailleurs : dans les réglages, pas en attendant.
        case fallbackUnauthorized
    }

    public static func translate(
        _ request: LocalLLMClient.Request,
        localBaseURL: URL?, localSession: URLSession,
        fallback: DeepLClient.Credentials?, fallbackSession: URLSession,
        fallbackRetryDelay: Duration = .seconds(2)
    ) async -> Outcome {
        if let localBaseURL, !request.model.isEmpty {
            switch await LocalLLMClient.translate(request, baseURL: localBaseURL,
                                                  session: localSession) {
            case .translated(let text):
                return .translated(text, by: .local)
            case .refusedTokens(let missing):
                guard let fallback else { return .refusedTokens(missing: missing) }
                return await viaFallback(request, fallback, fallbackSession,
                                         fallbackRetryDelay)
            case .endpointError(let message):
                guard let fallback else { return .endpointError(message) }
                return await viaFallback(request, fallback, fallbackSession,
                                         fallbackRetryDelay)
            }
        }
        // Aucun serveur local réglé : le secours, s'il existe, est tout ce
        // qu'on a. Sinon, le dire plutôt que de rendre une traduction vide.
        guard let fallback else { return .endpointError("aucune IA locale configurée") }
        return await viaFallback(request, fallback, fallbackSession, fallbackRetryDelay)
    }

    private static func viaFallback(
        _ request: LocalLLMClient.Request,
        _ credentials: DeepLClient.Credentials,
        _ session: URLSession,
        _ retryDelay: Duration
    ) async -> Outcome {
        switch await DeepLClient.translate(request.source,
                                           context: request.sectionLabel,
                                           credentials: credentials, session: session,
                                           retryDelay: retryDelay) {
        case .translated(let text):
            // Le gate de marques, sur le français **déballé** : sur le texte
            // enveloppé, chaque marque serait trouvée intacte dans sa balise
            // et le contrôle rendrait toujours vrai.
            // Le même filtre que le client local et que le chemin d'écriture :
            // toute divergence dure, la marque **dupliquée** comprise. Ne
            // retenir que les manquantes laissait passer un doublon que
            // `saveTranslation` refuserait ensuite — la clé finissait alors
            // dans les erreurs au lieu de la liste de ce qui reste à faire.
            let missing = TranslationTokenCheck
                .mismatches(source: request.source, target: text)
                .filter(\.isHard)
                .map(\.token)
            return missing.isEmpty ? .translated(text, by: .fallback)
                                   : .refusedTokens(missing: missing)
        case .quotaExhausted:
            return .quotaExhausted
        case .rateLimited:
            return .fallbackRateLimited
        case .unauthorized:
            return .fallbackUnauthorized
        case .rejected(let message), .transportError(let message):
            return .endpointError(message)
        }
    }
}
