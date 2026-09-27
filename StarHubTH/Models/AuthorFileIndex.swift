import Foundation

/// A1-T11 — tout ce que l'auteur d'un mod a livré, version par version :
/// les entrées d'installation du journal local et les fichiers Nexus au
/// format récent, ramenés au dossier du mod. Clés normalisées
/// (`ModFilePath.key`) → SHA-256.
public struct AuthorFileIndex: Sendable {
    public struct Version: Equatable, Sendable {
        public enum Source: Equatable, Sendable {
            case localHistory
            case nexus(fileId: Int)
        }
        public let source: Source
        public let version: String
        public let files: [String: String]

        public init(source: Source, version: String, files: [String: String]) {
            self.source = source
            self.version = version
            self.files = files
        }
    }

    /// Un fichier Nexus lu, avant d'être ramené au dossier du mod.
    public struct NexusFile: Sendable {
        public let fileId: Int
        public let version: String
        public let manifest: NexusFileManifest

        public init(fileId: Int, version: String, manifest: NexusFileManifest) {
            self.fileId = fileId
            self.version = version
            self.manifest = manifest
        }
    }

    public let versions: [Version]
    private let shasByKey: [String: Set<String>]

    public init(versions: [Version]) {
        self.versions = versions
        var shas: [String: Set<String>] = [:]
        for version in versions {
            for (key, sha) in version.files { shas[key, default: []].insert(sha) }
        }
        shasByKey = shas
    }

    /// Les versions locales (déjà relatives au dossier du mod, dans l'ordre du
    /// journal) et les fichiers Nexus que `NexusFileManifest.files(matching:)`
    /// sait ramener au dossier installé ; les autres sont écartés.
    public static func build(localVersions: [Version], nexus: [NexusFile],
                             installed: [String: String]) -> AuthorFileIndex {
        var versions = localVersions
        for file in nexus {
            guard let files = file.manifest.files(matching: installed) else { continue }
            versions.append(Version(source: .nexus(fileId: file.fileId),
                                    version: file.version, files: files))
        }
        return AuthorFileIndex(versions: versions)
    }

    /// Ces octets, à ce chemin, sortent d'une version de l'auteur.
    public func isAuthorFile(_ key: String, sha: String) -> Bool {
        shasByKey[key]?.contains(sha) == true
    }

    /// L'auteur a livré ce chemin, avec quelque octets que ce soit.
    public func shipsPath(_ key: String) -> Bool {
        shasByKey[key] != nil
    }

    /// La référence de la version installée : ce que l'auteur a livré pour
    /// elle, par clé (plusieurs empreintes quand plusieurs fichiers Nexus
    /// portent la même version).
    ///
    /// La dernière entrée du journal d'abord — **seulement si sa version est
    /// celle du `manifest.json` installé** : un mod remplacé à la main depuis
    /// n'a plus cette référence, et ses fichiers passeraient pour des
    /// retouches ou des suppressions. À défaut, l'union des fichiers Nexus de
    /// cette version (`NexusUpdateChecker.compare`, jamais en chaîne :
    /// `1.1` et `1.1.0` sont la même). `nil` sans l'une ni l'autre.
    public func reference(installedVersion: String) -> (files: [String: Set<String>], isLocal: Bool)? {
        if let local = versions.last(where: { $0.source == .localHistory }),
           NexusUpdateChecker.compare(local.version, installedVersion) == .orderedSame {
            return (local.files.mapValues { [$0] }, true)
        }
        var union: [String: Set<String>] = [:]
        for version in versions {
            guard case .nexus = version.source,
                  NexusUpdateChecker.compare(version.version, installedVersion) == .orderedSame
            else { continue }
            for (key, sha) in version.files { union[key, default: []].insert(sha) }
        }
        return union.isEmpty ? nil : (union, false)
    }
}
