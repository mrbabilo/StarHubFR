import Foundation

/// Deux mods qui réclament le même **nom logique** de dossier.
///
/// `ModItem.folderName` est logique : le point de tête d'un mod en pause en est
/// retiré, pour qu'une bascule ne fasse pas migrer la clé du registre, des
/// favoris, des notes ou des configurations par profil. Le prix de cette
/// stabilité : `X` actif et `.X` en pause portent le **même** `folderName`, et
/// rien ne garantit que ce soit le même mod.
///
/// Ce n'est pas un cas d'école. Sur le parc de l'auteur, mesuré le 2026-09-03 —
/// 1 075 dossiers à manifeste lisible pour **1 074 noms logiques** :
/// `[CP] Seaside Sounds` (`witchtopia.SeasideSounds`, actif) et
/// `.[CP] Seaside Sounds` (`Liana.SeasideSounds`, en pause) sont deux mods
/// différents, de deux auteurs différents.
///
/// Ce que la collision emporte : `ModItem.id` **est** `folderName`, donc les
/// deux mods partagent une identité `Identifiable` et un `ForEach` n'en rend
/// qu'un ; et tout ce qui s'indexe sur le dossier — identifiant Nexus,
/// catégorie, favori, note, configuration de profil, poids — est partagé.
///
/// ⚠️ Corriger cela en changeant `ModItem.id` serait une **migration**, pas un
/// correctif : ce champ est la clé de tous les magasins persistés. Ce fichier
/// se borne à empêcher le dégât irréversible — voir `isStaleDuplicate`.
public enum ModFolderCollision {

    /// Le dossier trouvé à destination d'une bascule est-il un **résidu de ce
    /// mod-là**, ou le dossier d'un autre mod ?
    ///
    /// `toggleMod` renomme `X` ↔ `.X` et, s'il trouve déjà quelque chose à
    /// destination, le met de côté sous un suffixe `.stale_…` avant d'écrire.
    /// Le raisonnement d'origine tenait : sur un renommage à parent identique,
    /// une collision ne pouvait être qu'un résidu de bascule plantée. La
    /// collision mesurée le dément — c'est un autre mod, installé et actif, qui
    /// se ferait déplacer, avec ses favoris, sa note et sa configuration
    /// laissés derrière.
    ///
    /// - Parameters:
    ///   - destinationUniqueId: l'`UniqueID` lu dans le manifeste du dossier
    ///     déjà présent à destination. `nil` ou vide quand il n'y en a pas.
    ///   - uniqueId: celui du mod qu'on bascule.
    /// - Returns: `true` s'il est légitime de mettre ce dossier de côté.
    ///
    /// Un manifeste illisible à destination compte comme un résidu : une
    /// bascule interrompue laisse justement un dossier à moitié écrit, et
    /// refuser là-dessus bloquerait la réparation que ce mécanisme existe pour
    /// faire. À l'inverse, sans identité du côté qu'on bascule, on ne compare
    /// rien — et ce qu'on ne sait pas ne justifie pas de déplacer le dossier
    /// d'autrui.
    ///
    /// La comparaison ignore la casse, comme SMAPI : un manifeste réédité avec
    /// une majuscule différente ne fait pas un autre mod.
    public static func isStaleDuplicate(destinationUniqueId: String?,
                                        toggling uniqueId: String) -> Bool {
        let destination = (destinationUniqueId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { return true }
        let toggled = uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toggled.isEmpty else { return false }
        return destination.lowercased() == toggled.lowercased()
    }

    /// Le nom sous lequel écarter un dossier qui occupe la destination d'une
    /// bascule, avant de tenter le renommage.
    ///
    /// **Le point de tête n'est pas décoratif.** Le dossier écarté reste dans
    /// `Mods/` le temps du renommage — et, si le nettoyage échoue ou que l'app
    /// s'arrête entre-temps, bien plus longtemps. Sans point, SMAPI le charge :
    /// il déclare alors le même `UniqueID` que le dossier qui vient de prendre
    /// sa place, et le jeu signale un doublon. Les deux chemins de bascule
    /// n'écrivaient pas la même chose ici — l'un préfixait, l'autre non.
    ///
    /// Le suffixe aléatoire évite qu'un second écart percute le premier.
    public static func asideName(for physicalFolderName: String) -> String {
        let dotted = physicalFolderName.hasPrefix(".")
            ? physicalFolderName
            : "." + physicalFolderName
        return "\(dotted).stale_\(UUID().uuidString)"
    }

    /// Un mod tel qu'il revendique son dossier.
    public struct Claim: Equatable, Sendable {
        public let folderName: String
        public let uniqueId: String
        /// Le nom **sur le disque** — celui-là porte le point de tête d'un mod
        /// en pause, et c'est justement lui qui distingue les deux prétendants.
        /// Sans lui, on saurait nommer la collision sans savoir où la montrer.
        public let physicalFolderName: String

        public init(folderName: String, uniqueId: String, physicalFolderName: String) {
            self.folderName = folderName
            self.uniqueId = uniqueId
            self.physicalFolderName = physicalFolderName
        }
    }

    /// Un nom de dossier réclamé par plusieurs identités.
    public struct Collision: Equatable, Sendable {
        public let folderName: String
        /// Les identités en présence, triées : deux affichages successifs ne
        /// doivent pas permuter la liste.
        public let uniqueIds: [String]
        /// Les dossiers **réels** des prétendants, triés eux aussi. C'est ce
        /// qu'on donne au Finder : montrer les deux côte à côte est la seule
        /// façon honnête de désigner une collision — ouvrir « le » dossier
        /// choisirait au hasard entre les deux, ce que la ligne dénonce.
        public let physicalFolderNames: [String]

        public init(folderName: String, uniqueIds: [String],
                    physicalFolderNames: [String]) {
            self.folderName = folderName
            self.uniqueIds = uniqueIds
            self.physicalFolderNames = physicalFolderNames
        }
    }

    /// Les noms logiques que plusieurs mods **distincts** revendiquent.
    ///
    /// Une même identité vue deux fois n'en est pas une : un scan concurrent ou
    /// un pack déplié en double n'oppose personne. Les mods sans `UniqueID` —
    /// 111 sur le parc — sont écartés : ils ne peuvent témoigner d'aucune
    /// collision d'identité.
    public static func collisions(_ claims: [Claim]) -> [Collision] {
        var identitiesByFolder: [String: Set<String>] = [:]
        var pathsByFolder: [String: Set<String>] = [:]
        var displayByLowercased: [String: String] = [:]
        for claim in claims where !claim.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty && !claim.folderName.isEmpty {
            let folded = claim.uniqueId.lowercased()
            identitiesByFolder[claim.folderName, default: []].insert(folded)
            if !claim.physicalFolderName.isEmpty {
                pathsByFolder[claim.folderName, default: []].insert(claim.physicalFolderName)
            }
            // La première orthographe rencontrée fait foi pour l'affichage :
            // c'est un nom montré à l'utilisateur, pas une clé.
            if displayByLowercased[folded] == nil { displayByLowercased[folded] = claim.uniqueId }
        }
        return identitiesByFolder
            .filter { $0.value.count > 1 }
            .map { folder, identities in
                Collision(folderName: folder,
                          uniqueIds: identities.map { displayByLowercased[$0] ?? $0 }.sorted(),
                          physicalFolderNames: (pathsByFolder[folder] ?? []).sorted())
            }
            .sorted { $0.folderName < $1.folderName }
    }
}
