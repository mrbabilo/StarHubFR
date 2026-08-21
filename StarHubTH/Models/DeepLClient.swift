import Foundation

/// L'appel à DeepL, et rien de plus : l'ordre des tentatives vit dans
/// `TranslationEngine`, la protection des marques dans `TokenShield`.
public enum DeepLClient {

    /// Une clé d'API et l'hôte qu'elle désigne.
    public struct Credentials: Equatable, Sendable {
        public let key: String

        /// `nil` pour une clé vide : pas d'identifiants, donc pas de secours.
        public init?(key: String) {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            self.key = trimmed
        }

        /// Le suffixe `:fx` marque une clé du plan gratuit (documentation
        /// DeepL) — l'utilisateur n'a donc jamais à choisir son hôte.
        public var isFreePlan: Bool { key.hasSuffix(":fx") }

        public var baseURL: URL {
            // Deux hôtes constants et valides : le repli ne peut pas servir.
            URL(string: isFreePlan ? "https://api-free.deepl.com"
                                   : "https://api.deepl.com")!
        }
    }
}
