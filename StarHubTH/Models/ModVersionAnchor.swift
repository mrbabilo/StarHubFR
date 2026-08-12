import Foundation

/// Ce que l'app **affirme** avoir installé pour un mod, et d'où vient
/// l'affirmation.
///
/// Le défaut que ce type remplace : le registre enregistrait la dernière
/// version *publiée* sur Nexus comme version installée, sans qu'aucune
/// installation ne l'atteste. Le vérificateur comparait alors cette version à
/// elle-même, concluait « à jour », et la mise à jour s'effaçait. 52 mods du
/// parc portaient ainsi une version que leur manifest ne déclarait pas.
///
/// La règle qui en découle tient en une phrase : **une ancre ne se pose que
/// sur un constat.** Sans ancre, on n'affirme rien — on envoie la version du
/// manifest telle quelle.
///
/// Clé : le `UniqueID`, pas l'identifiant Nexus. Sur le parc réel, 58
/// identifiants Nexus sont portés par plusieurs dossiers, dont 19 packs posés
/// à plat aux versions divergentes, et l'identifiant 8828 rassemble trois mods
/// sans rapport. Le `UniqueID` est ce que le jeu charge et ce que smapi.io
/// interroge.
public struct ModVersionAnchor: Codable, Equatable {
    public let uniqueId: String
    /// La version affirmée. C'est elle qu'on envoie comme `installedVersion`.
    public let anchoredVersion: String
    public let origin: Origin
    public let anchoredAt: Date
    /// Renseigné seulement quand l'app a posé le fichier elle-même.
    public let nexusFacts: NexusInstallFacts?

    /// Il n'existe pas de cas « supposé » : c'est délibéré. Une valeur pour
    /// « je crois savoir » finirait par être lue comme un constat.
    public enum Origin: String, Codable {
        case install       // installation constatée par l'app
        case userAffirmed  // « je l'ai déjà »
        case diskObserved  // la version du manifest a changé et rejoint la cible
    }

    public init(uniqueId: String,
                anchoredVersion: String,
                origin: Origin,
                anchoredAt: Date,
                nexusFacts: NexusInstallFacts? = nil) {
        self.uniqueId = uniqueId
        self.anchoredVersion = anchoredVersion
        self.origin = origin
        self.anchoredAt = anchoredAt
        self.nexusFacts = nexusFacts
    }
}

/// Ce que Nexus a dit du fichier au moment où l'app l'a posé.
///
/// `fileUploadedAt` porte la règle de re-publication à version constante (lot
/// C) : un auteur qui republie un correctif sous le même numéro est invisible
/// à toute comparaison de chaînes. C'est la règle qui a trouvé la seule mise à
/// jour réelle du cache actuel.
public struct NexusInstallFacts: Codable, Equatable {
    public let modId: String
    public let fileId: Int
    public let fileUploadedAt: Date
    /// « Original upload » de la page. Renseigne, ne décide pas.
    public let pageCreatedAt: Date?

    public init(modId: String, fileId: Int, fileUploadedAt: Date, pageCreatedAt: Date? = nil) {
        self.modId = modId
        self.fileId = fileId
        self.fileUploadedAt = fileUploadedAt
        self.pageCreatedAt = pageCreatedAt
    }
}
