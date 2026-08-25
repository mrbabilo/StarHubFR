import Foundation

/// Traduire des mods **favoris** en identifiants de profil.
///
/// Les deux bouts ne parlent pas la même langue : un favori est marqué sur une
/// ligne de liste, donc désigné par son `folderName` — le nom logique, qui
/// survit à une mise en pause. Un profil, lui, ne connaît que des `UniqueID`.
/// Entre les deux il y a les packs : un dossier de premier niveau qui porte
/// plusieurs mods, sans identifiant à lui.
///
/// Type pur, testé : c'est la seule vraie logique de la fonctionnalité, et
/// elle décide de ce qui entre dans un profil.
public enum FavoriteResolution {
    public struct Result: Equatable {
        /// Les `UniqueID` à ajouter au profil, dans l'ordre des favoris et
        /// sans ceux qu'il contient déjà.
        public let ids: [String]
        /// Les favoris qu'on n'a pas su traduire, par leur nom de dossier :
        /// un mod désinstallé depuis, ou dont le manifeste n'annonce pas
        /// d'identifiant. **À dire à l'utilisateur** — les écarter en silence
        /// donnerait un import qui prétend avoir tout pris.
        public let unresolved: [String]

        public init(ids: [String], unresolved: [String]) {
            self.ids = ids
            self.unresolved = unresolved
        }
    }

    /// - Parameters:
    ///   - favorites: noms de dossiers **logiques** marqués comme favoris.
    ///   - mods: les mods de premier niveau (en-têtes de pack compris), tels
    ///     que la liste les montre. Un favori ne se marque que là : un
    ///     composant de pack ne s'active pas seul, c'est le pack qui est
    ///     l'unité qu'on met en pause ou qu'on installe.
    ///   - existing: ce que le profil contient déjà.
    public static func profileIds(favorites: Set<String>,
                                  in mods: [ModItem],
                                  existing: [String] = []) -> Result {
        // La comparaison des identifiants ignore la casse, comme
        // `addModToProfile` : deux entrées qui ne diffèrent que par elle
        // donneraient deux lignes de même identité à un `ForEach`, avec les
        // lignes fantômes que ça entraîne.
        var seen = Set(existing.map { $0.lowercased() })
        var ids: [String] = []
        var unresolved: [String] = []

        // Trié : l'ordre d'un `Set` n'est pas un contrat, et deux imports du
        // même jeu de favoris doivent donner le même profil.
        for favorite in favorites.sorted() {
            guard let mod = mods.first(where: { $0.folderName == favorite }) else {
                unresolved.append(favorite)
                continue
            }

            // Un pack n'a pas d'identifiant à lui : ce sont ses composants qui
            // entrent dans le profil, exactement comme quand la bissection
            // traduit des dossiers actifs en profil éphémère.
            let candidates = mod.isGroup
                ? (mod.children ?? []).map(\.uniqueId)
                : [mod.uniqueId]
            let usable = candidates.filter { !$0.isEmpty }
            guard !usable.isEmpty else {
                unresolved.append(favorite)
                continue
            }

            for id in usable where seen.insert(id.lowercased()).inserted {
                ids.append(id)
            }
        }

        return Result(ids: ids, unresolved: unresolved)
    }
}
