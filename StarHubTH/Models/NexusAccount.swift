import Foundation

/// Ce que Nexus dit du compte dont on porte la clé.
///
/// Une seule chose en découle vraiment : **le téléchargement direct par l'API
/// est réservé aux comptes premium**. Sans ce renseignement, l'app propose un
/// bouton qui échouera à coup sûr, et l'utilisateur découvre la règle par un
/// message d'erreur — vérifié sur un compte réel, `/download_link.json` répond
/// alors `403 « this is for premium users only »`.
///
/// ⚠️ **Le quota d'API ne dit rien du statut premium.** Un compte gratuit muni
/// d'une clé personnelle lit 2 000 requêtes par heure et 20 000 par jour,
/// exactement comme un premium. Déduire l'un de l'autre est une erreur — celle
/// qui a fait prendre un message d'erreur juste pour un défaut de l'app.
public struct NexusAccount: Codable, Equatable, Sendable {
    public let name: String
    public let isPremium: Bool
    /// Quand le renseignement a été obtenu.
    public let checkedAt: Date

    public init(name: String, isPremium: Bool, checkedAt: Date) {
        self.name = name
        self.isPremium = isPremium
        self.checkedAt = checkedAt
    }

    /// Lit la réponse de `/v1/users/validate.json`.
    ///
    /// La réponse réelle porte le statut sous **trois** clés à la fois —
    /// `is_premium`, `is_premium?` et parfois `is_supporter` — sans qu'aucune
    /// documentation ne dise laquelle fait foi. Les deux premières sont donc
    /// acceptées : n'en lire qu'une exposerait à ce qu'un renommage fasse
    /// passer un compte premium pour gratuit, et prive l'utilisateur d'un
    /// bouton auquel il a droit.
    public init?(json: [String: Any], now: Date = Date()) {
        let premium = (json["is_premium"] as? Bool)
            ?? (json["is_premium?"] as? Bool)
            ?? (json["is_premium"] as? NSNumber)?.boolValue
        guard let premium else { return nil }
        self.init(name: json["name"] as? String ?? "",
                  isPremium: premium, checkedAt: now)
    }

    /// Le renseignement vieillit : un compte peut devenir premium, ou cesser de
    /// l'être. Une semaine, c'est assez court pour ne pas mentir longtemps, et
    /// assez long pour ne pas interroger Nexus à chaque lancement.
    public func isStale(now: Date = Date()) -> Bool {
        now >= checkedAt.addingTimeInterval(7 * 24 * 3600)
    }
}
