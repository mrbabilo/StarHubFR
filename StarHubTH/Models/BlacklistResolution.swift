import Foundation

/// Traduire des mods **« à écarter »** (blacklist) en identifiants de profil.
///
/// Symétrique de `FavoriteResolution` à un nom près : la source est une
/// `Set<String>` de `folderName` marqués à écarter, la cible une liste
/// d'`UniqueID` prêts à entrer dans un profil. Mêmes arbitrages — packs,
/// casse, déduplication, tri déterministe — pour les mêmes raisons ; voir le
/// commentaire de `FavoriteResolution.profileIds` pour le détail.
///
/// Type pur, testé : c'est la seule vraie logique de la fonctionnalité, et
/// elle décide de ce qui entre dans un profil.
public enum BlacklistResolution {
    public struct Result: Equatable {
        /// Les `UniqueID` à ajouter au profil, dans l'ordre des mods à
        /// écarter et sans ceux qu'il contient déjà.
        public let ids: [String]
        /// Les mods à écarter qu'on n'a pas su traduire, par leur nom de
        /// dossier : un mod désinstallé depuis, ou dont le manifeste
        /// n'annonce pas d'identifiant. **À dire à l'utilisateur** — les
        /// écarter en silence donnerait un import qui prétend avoir tout
        /// pris.
        public let unresolved: [String]

        public init(ids: [String], unresolved: [String]) {
            self.ids = ids
            self.unresolved = unresolved
        }
    }

    /// - Parameters:
    ///   - blacklist: noms de dossiers **logiques** marqués à écarter.
    ///   - mods: les mods de premier niveau (en-têtes de pack compris),
    ///     tels que la liste les montre. Une marque ne se pose que là :
    ///     un composant de pack ne se pilote pas seul.
    ///   - existing: ce que le profil contient déjà.
    public static func profileIds(blacklist: Set<String>,
                                  in mods: [ModItem],
                                  existing: [String] = []) -> Result {
        var seen = Set(existing.map { $0.lowercased() })
        var ids: [String] = []
        var unresolved: [String] = []

        for marked in blacklist.sorted() {
            guard let mod = mods.first(where: { $0.folderName == marked }) else {
                unresolved.append(marked)
                continue
            }

            let candidates = mod.components.map(\.uniqueId)
            let usable = candidates.filter { !$0.isEmpty }
            guard !usable.isEmpty else {
                unresolved.append(marked)
                continue
            }

            for id in usable where seen.insert(id.lowercased()).inserted {
                ids.append(id)
            }
        }

        return Result(ids: ids, unresolved: unresolved)
    }
}