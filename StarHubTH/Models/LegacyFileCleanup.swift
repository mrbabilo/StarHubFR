import Foundation

/// A1-T11 plan 2 — ce que « Nettoyer les anciens fichiers » propose de
/// retirer d'un mod : les fichiers laissés par d'anciennes versions de
/// l'auteur, déjà présents avant le tri par provenance (plan 1).
///
/// Un fichier n'est proposé que s'il est **absent de la référence** de la
/// version installée (ce que l'auteur livre pour elle), et :
/// - **identique** à un fichier de l'auteur déposé **avant** la référence
///   (octets prouvés : journal local ou manifeste Nexus récent) — coché ;
/// - ou **probable** : son chemin figurait dans un dépôt antérieur au format
///   ancien (chemins seuls) — décoché, jamais une traduction.
///
/// « Avant » se lit dans l'ordre des dépôts Nexus (`fileId`), jamais dans
/// l'étiquette de version : Wildroot étiquette « 14 » des fichiers antérieurs
/// à sa 1.4.1, et un auteur qui oublie de relever son `manifest.json` ferait
/// passer les fichiers neufs de la version réellement installée pour des
/// fantômes cochés. Référence du journal local : pas de borne, c'est
/// l'archive exacte que l'app a posée.
///
/// Sans référence, rien : on ne sait pas ce que la version installée livre.
/// Spec : `docs/superpowers/specs/2026-09-27-a1-t11-update-triage-design.md`.
public enum LegacyFileCleanup {
    public enum Certainty: Equatable, Sendable {
        case identical
        case pathOnly
    }

    public struct Candidate: Equatable, Sendable, Identifiable {
        /// Chemin relatif **du disque**.
        public let path: String
        public let size: Int64
        public let sha256: String
        public let certainty: Certainty
        public var id: String { path }

        public init(path: String, size: Int64, sha256: String, certainty: Certainty) {
            self.path = path
            self.size = size
            self.sha256 = sha256
            self.certainty = certainty
        }
    }

    /// D'où vient la référence de la version installée.
    public enum ReferenceSource: Equatable, Sendable {
        case localHistory
        case nexusRecent
        case nexusLegacy
    }

    /// Un fichier Nexus au format ancien, ramené au dossier du mod
    /// (`NexusLegacyFileManifest.paths(matching:)`).
    public struct LegacyVersion: Equatable, Sendable {
        public let fileId: Int
        public let version: String
        public let paths: Set<String>

        public init(fileId: Int, version: String, paths: Set<String>) {
            self.fileId = fileId
            self.version = version
            self.paths = paths
        }
    }

    public struct Plan: Equatable, Sendable {
        /// Triés par chemin.
        public let candidates: [Candidate]
        public let reference: ReferenceSource
        /// La lecture Nexus n'a pas abouti : la liste peut être plus courte.
        public let nexusIncomplete: Bool
    }

    public enum Outcome: Equatable, Sendable {
        case noReference
        case plan(Plan)
    }

    /// - Parameters:
    ///   - installed: le dossier du mod (`ModFolderHasher.listing`).
    ///   - index: journal local + Nexus au format récent.
    ///   - legacy: Nexus au format ancien, déjà ramené au dossier.
    ///   - installedVersion: la `Version` du `manifest.json` installé.
    ///   - deposits: clés des fichiers déposés par l'app (jamais proposés).
    public static func plan(installed: ModFolderHasher.Listing, index: AuthorFileIndex,
                            legacy: [LegacyVersion], installedVersion: String,
                            deposits: Set<String>, nexusIncomplete: Bool) -> Outcome {
        func isInstalledVersion(_ version: String) -> Bool {
            NexusUpdateChecker.compare(version, installedVersion) == .orderedSame
        }
        let referenceKeys: Set<String>
        let source: ReferenceSource
        /// Dépôts Nexus antérieurs à la référence : `fileId` strictement plus petit.
        let bound: Int
        if let reference = index.reference(installedVersion: installedVersion) {
            referenceKeys = Set(reference.files.keys)
            source = reference.isLocal ? .localHistory : .nexusRecent
            bound = reference.isLocal ? .max : index.versions.compactMap { version -> Int? in
                guard case .nexus(let fileId) = version.source, isInstalledVersion(version.version) else { return nil }
                return fileId
            }.max() ?? 0
        } else {
            let same = legacy.filter { isInstalledVersion($0.version) }
            guard let newest = same.map(\.fileId).max() else { return .noReference }
            referenceKeys = same.reduce(into: Set<String>()) { $0.formUnion($1.paths) }
            source = .nexusLegacy
            bound = newest
        }

        var earlierShas: [String: Set<String>] = [:]
        for version in index.versions {
            switch version.source {
            case .localHistory: break
            case .nexus(let fileId): guard fileId < bound else { continue }
            }
            for (key, sha) in version.files { earlierShas[key, default: []].insert(sha) }
        }
        let earlierPaths = legacy
            .filter { $0.fileId < bound && !isInstalledVersion($0.version) }
            .reduce(into: Set<String>()) { $0.formUnion($1.paths) }
        let nested = nestedModRoots(installed.hashes.keys.map(ModFilePath.key))

        var candidates: [Candidate] = []
        for (path, sha) in installed.hashes {
            let key = ModFilePath.key(path)
            if nested.contains(where: { key.hasPrefix($0) }) { continue }
            if referenceKeys.contains(key) || deposits.contains(key) { continue }
            let name = ModFilePath.lastComponent(key)
            if name == "config.json" || name == "manifest.json" { continue }
            let certainty: Certainty
            if earlierShas[key]?.contains(sha) == true {
                certainty = .identical
            } else if earlierPaths.contains(key), !ModFilePath.isTranslation(key) {
                certainty = .pathOnly
            } else {
                continue
            }
            candidates.append(Candidate(path: path, size: installed.sizes[path] ?? 0,
                                        sha256: sha, certainty: certainty))
        }
        return .plan(Plan(candidates: candidates.sorted { $0.path < $1.path },
                          reference: source, nexusIncomplete: nexusIncomplete))
    }

    /// Les sous-dossiers qui portent leur propre `manifest.json` : d'autres
    /// mods, rangés dans celui-ci. Leurs fichiers ne sont jamais proposés.
    static func nestedModRoots(_ keys: [String]) -> [String] {
        keys.compactMap { key in
            guard key.hasSuffix("/manifest.json") else { return nil }
            return String(key.dropLast("manifest.json".count))
        }
    }
}
