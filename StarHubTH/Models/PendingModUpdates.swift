import Foundation

/// La mise à jour qu'un mod attend, lue sur sa ligne, sa carte et sa fiche
/// (I-T13) — les mêmes sources que le badge « Mises à jour ».
///
/// **Appariement par `UniqueID`, jamais par identifiant Nexus.** 58
/// identifiants Nexus sont partagés sur le parc, et `Nexus:8828` couvre trois
/// mods sans rapport : allumer par l'identifiant Nexus désignerait le mauvais
/// mod. La ligne Nexus consolidée d'un pack porte l'`UniqueID` du composant
/// retenu (`NexusUpdateConsolidation`) : l'en-tête s'allume par cet enfant.
///
/// Le relevé SMAPI n'a pas d'`UniqueID`, seulement le nom journalisé :
/// l'appelant le résout en dossier (`resolveModFolder(forLoggedName:)`, même
/// chaîne que le badge, X113) et une entrée non résolue n'allume rien.
public struct PendingModUpdates: Equatable, Sendable {

    public struct Pending: Equatable, Sendable {
        public enum Source: Equatable, Sendable {
            /// Vérification smapi.io/Nexus : porte les gestes (MàJ Premium,
            /// page Nexus, « Je l'ai déjà », veille). `uniqueId` retrouve la
            /// ligne d'origine.
            case nexus(uniqueId: String)
            /// Relevé du journal SMAPI : un lien smapi.io, rien d'autre.
            case smapi(url: String)
        }
        public let availableVersion: String
        public let source: Source
    }

    private let byUniqueId: [String: Pending]
    private let byFolder: [String: Pending]

    public static let empty = PendingModUpdates(nexus: [], smapi: [])

    /// - Parameters:
    ///   - nexus: les lignes dues (veilles et « Je l'ai déjà » déjà ôtées).
    ///   - smapi: les entrées du relevé que le disque ne couvre pas, résolues
    ///     en dossier logique.
    public init(nexus: [(uniqueId: String, latestVersion: String)],
                smapi: [(folderName: String, version: String, url: String)]) {
        var ids: [String: Pending] = [:]
        // Un identifiant vide n'est la clé de personne (111 mods du parc).
        for row in nexus where !row.uniqueId.isEmpty {
            ids[row.uniqueId.lowercased()] = Pending(availableVersion: row.latestVersion,
                                                    source: .nexus(uniqueId: row.uniqueId))
        }
        var folders: [String: Pending] = [:]
        for row in smapi {
            folders[row.folderName] = Pending(availableVersion: row.version,
                                              source: .smapi(url: row.url))
        }
        byUniqueId = ids
        byFolder = folders
    }

    /// La mise à jour du mod, ou de l'un de ses composants pour un en-tête de
    /// pack. Nexus prime sur SMAPI : c'est lui qui porte les gestes.
    public func pending(for mod: ModItem) -> Pending? {
        let candidates = [mod] + (mod.children ?? [])
        for candidate in candidates {
            if let hit = byUniqueId[candidate.uniqueId.lowercased()] {
                return hit
            }
        }
        for candidate in candidates {
            if let hit = byFolder[candidate.folderName] { return hit }
        }
        return nil
    }
}
