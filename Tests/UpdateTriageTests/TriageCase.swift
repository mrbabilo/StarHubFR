import Foundation
@testable import StarHubTHCore

extension Fixture {
    /// Un cas de tri : le dossier installé, l'archive neuve et les versions
    /// Nexus au format récent (chemins relatifs à l'archive). Empreintes
    /// tronquées à 16 caractères : le tri ne fait que les comparer.
    struct TriageCase: Decodable {
        struct NexusVersion: Decodable {
            let fileId: Int
            let version: String
            let files: [String: String]
        }
        let name: String
        let installedVersion: String
        let installed: [String: String]
        let newArchive: [String: String]
        let versions: [NexusVersion]

        var installedListing: ModFolderHasher.Listing { .init(hashes: installed) }
        var newListing: ModFolderHasher.Listing { .init(hashes: newArchive) }

        func index(local: [AuthorFileIndex.Version] = []) -> AuthorFileIndex {
            AuthorFileIndex.build(
                localVersions: local,
                nexus: versions.map {
                    .init(fileId: $0.fileId, version: $0.version,
                          manifest: NexusFileManifest(archiveSHA256: nil, repackedSHA256: nil,
                                                      files: $0.files))
                },
                installed: installedListing.byKey)
        }

        func plan(local: [AuthorFileIndex.Version] = [], deposits: Set<String> = []) -> UpdateFileTriage.Plan {
            UpdateFileTriage.plan(installed: installedListing, newArchive: newListing,
                                  index: index(local: local), installedVersion: installedVersion,
                                  deposits: deposits)
        }
    }

    static func triageCase(_ name: String) throws -> TriageCase {
        try JSONDecoder().decode(TriageCase.self, from: data("triage-\(name).json"))
    }
}
