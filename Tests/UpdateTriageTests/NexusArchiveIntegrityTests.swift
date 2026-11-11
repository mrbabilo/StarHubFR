import Foundation
import Testing
@testable import StarHubTHCore

/// Une archive téléchargée de Nexus est comparée à l'empreinte que Nexus
/// publie **pour ce fichier** (relevé des sources du 2026-11-11, idée de
/// JuniGrid 1.3.0). Sans manifeste, on s'abstient.
struct NexusArchiveIntegrityTests {
    private typealias Integrity = NexusArchiveIntegrity
    private typealias Fetcher = NexusFileManifestFetcher

    private func manifest(archive: String?, repacked: String? = nil) -> NexusFileManifest {
        NexusFileManifest(archiveSHA256: archive, repackedSHA256: repacked, files: [:])
    }

    @Test func eitherPublishedFingerprintVerifiesWhateverTheCase() {
        #expect(Integrity.verdict(archiveSHA256: "ABC", manifest: manifest(archive: "abc")) == .verified)
        #expect(Integrity.verdict(archiveSHA256: "def", manifest: manifest(archive: "abc", repacked: "DEF")) == .verified)
        #expect(Integrity.verdict(archiveSHA256: "000", manifest: manifest(archive: "abc", repacked: "def")) == .mismatch)
    }

    @Test func withoutSomethingToCompareNothingIsConcluded() {
        #expect(Integrity.verdict(archiveSHA256: "abc", manifest: nil) == .unverifiable)
        #expect(Integrity.verdict(archiveSHA256: nil, manifest: manifest(archive: "abc")) == .unverifiable)
        #expect(Integrity.verdict(archiveSHA256: "abc", manifest: manifest(archive: nil)) == .unverifiable)
    }

    // MARK: - Lecture du manifeste d'un fichier, puis vérification

    /// Un faux Nexus : deux fichiers de **même version** (principal et
    /// optionnel, cas de trois pages du parc) et un fichier ancien.
    private static func nexus(archiveSha: String, manifestStatus: Int = 200) -> Fetcher.Transport {
        { request in
            let url = request.url?.absoluteString ?? ""
            if url.hasSuffix("/v2/graphql") {
                let json = #"{"data":{"modFiles":["#
                    + #"{"fileId":10,"version":"1.0.0","uri":"aa/bb/cc/aabbcc01-0000-4000-8000-000000000001","date":1700000000},"#
                    + #"{"fileId":11,"version":"1.0.0","uri":"aa/bb/cc/aabbcc02-0000-4000-8000-000000000002","date":1700000000},"#
                    + #"{"fileId":9,"version":"0.9.0","uri":"Old Mod 0.9-123-0-9-1580000000.zip","date":1580000000}"#
                    + "]}}"
                return .init(body: Data(json.utf8), status: 200)
            }
            // Le fichier 10 a l'empreinte donnée, le 11 une autre.
            let sha = url.hasSuffix("000000000001") ? archiveSha : "ffff"
            let json = #"{"archive":{"hashes":{"SHA256":"\#(sha)"}},"files":[]}"#
            return .init(body: Data(json.utf8), status: manifestStatus)
        }
    }

    private func archive(_ content: String) throws -> (URL, String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("integrity-\(UUID().uuidString).zip")
        try Data(content.utf8).write(to: url)
        return (url, try ModFolderHasher.sha256(of: url))
    }

    @Test func theDownloadedFileIsComparedToItsOwnManifestNotToItsSibling() throws {
        let (url, sha) = try archive("archive intacte")
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = Self.nexus(archiveSha: sha.uppercased())
        #expect(Integrity.check(archive: url, modId: 123, fileId: 10, cacheDirectory: nil, transport: transport) == .verified)
        // Même version, autre fichier : ce n'est pas son empreinte.
        #expect(Integrity.check(archive: url, modId: 123, fileId: 11, cacheDirectory: nil, transport: transport) == .mismatch)
    }

    @Test func anAlteredArchiveIsCaught() throws {
        let (url, _) = try archive("archive tronquée")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(Integrity.check(archive: url, modId: 123, fileId: 10, cacheDirectory: nil,
                                transport: Self.nexus(archiveSha: "abc")) == .mismatch)
    }

    /// Format ancien, fichier absent de la liste, manifeste 404 : on s'abstient.
    @Test func noManifestMeansNoVerdict() throws {
        let (url, _) = try archive("x")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(Integrity.check(archive: url, modId: 123, fileId: 9, cacheDirectory: nil,
                                transport: Self.nexus(archiveSha: "abc")) == .unverifiable)
        #expect(Integrity.check(archive: url, modId: 123, fileId: 99, cacheDirectory: nil,
                                transport: Self.nexus(archiveSha: "abc")) == .unverifiable)
        #expect(Integrity.check(archive: url, modId: 123, fileId: 10, cacheDirectory: nil,
                                transport: Self.nexus(archiveSha: "abc", manifestStatus: 404)) == .unverifiable)
    }
}
