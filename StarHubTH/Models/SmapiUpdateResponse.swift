import Foundation

/// Décodage de la réponse de `smapi.io/api/v3.0/mods`, et classement de ses
/// erreurs.
///
/// Presque tout y est optionnel, et ce n'est pas de la prudence gratuite :
/// mesuré sur 960 mods, `metadata` se réduit souvent à un tableau `id` vide
/// pour les mods que la base ne connaît pas. Exiger `name` ou `nexusID` ferait
/// échouer le décodage d'un lot de 150 à cause d'un seul mod obscur.
public enum SmapiUpdateResponse {

    public struct Version: Decodable, Equatable {
        public let version: String
        public let url: String?
    }

    public struct Metadata: Decodable, Equatable {
        public let name: String?
        public let nexusID: Int?
        public let main: Version?
        public let unofficial: Version?
        public let compatibilityStatus: String?
        public let compatibilitySummary: String?
        /// La version du jeu qui a cassé le mod — « Stardew Valley 1.6 ».
        /// Présente sur **les sept mods signalés** du parc réel, et jamais
        /// décodée jusqu'ici : c'est elle qui distingue « ce mod a planté » de
        /// « ce mod est cassé depuis la 1.6 ».
        public let brokeIn: String?
    }

    public struct Mod: Decodable, Equatable {
        public let id: String
        public let suggestedUpdate: Version?
        public let metadata: Metadata?
        public let errors: [String]

        enum CodingKeys: String, CodingKey {
            case id, suggestedUpdate, metadata, errors
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            suggestedUpdate = try c.decodeIfPresent(Version.self, forKey: .suggestedUpdate)
            metadata = try c.decodeIfPresent(Metadata.self, forKey: .metadata)
            errors = try c.decodeIfPresent([String].self, forKey: .errors) ?? []
        }
    }

    /// Ce qui empêche un mod d'être vérifié. 115 mods du parc réel en portent
    /// un — et c'est le silence sur ces 115 qui a rendu le défaut d'origine si
    /// coûteux : rien ne les distinguait à l'écran d'un mod vérifié et à jour.
    public enum Blocker: String, Equatable {
        /// `UpdateKeys` qui n'est pas un entier : `Nexus:auteur.mod`. 35 cas.
        case malformedNexusId
        /// La page n'existe pas (retirée, cachée, identifiant faux). 31 cas.
        case sourceNotFound
        /// La page existe mais ne publie aucune version exploitable. 33 cas.
        case noValidVersion
        /// La clé n'a pas la forme `Site:identifiant`. 13 cas.
        case malformedUpdateKey
        /// Famille inconnue : le texte d'origine reste affichable.
        case other

        /// La clé de libellé localisé qui nomme ce motif dans la fenêtre des
        /// mises à jour. Le mappage vit ici — côté Core, testé — pour que la
        /// vue ne porte qu'un rendu, jamais un `switch` à maintir en deux
        /// langues.
        public var labelKey: String {
            switch self {
            case .malformedNexusId:   L10n.Updates.blockerMalformedNexusId
            case .sourceNotFound:     L10n.Updates.blockerSourceNotFound
            case .noValidVersion:     L10n.Updates.blockerNoValidVersion
            case .malformedUpdateKey: L10n.Updates.blockerMalformedUpdateKey
            case .other:              L10n.Updates.blockerOther
            }
        }
    }

    public static func decode(_ data: Data) throws -> [Mod] {
        try JSONDecoder().decode([Mod].self, from: data)
    }

    /// Les messages de smapi.io sont des phrases anglaises libres, sans code.
    /// On les classe sur des fragments stables — l'ordre des tests compte, la
    /// clé mal formée mentionnant elle aussi « update key ».
    public static func blocker(for message: String) -> Blocker {
        let m = message.lowercased()
        if m.contains("isn't a valid nexus mod id") { return .malformedNexusId }
        if m.contains("has no valid versions") { return .noValidVersion }
        if m.contains("isn't in a valid format") { return .malformedUpdateKey }
        if m.contains("found no") { return .sourceNotFound }
        return .other
    }
}
