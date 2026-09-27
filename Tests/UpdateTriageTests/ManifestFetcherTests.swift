import Foundation
import Testing
@testable import StarHubTHCore

struct ManifestFetcherTests {
    private typealias Fetcher = NexusFileManifestFetcher

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManifestFetcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Un faux Nexus : `modFiles` rend trois fichiers (deux récents, un
    /// ancien) ; les manifestes répondent selon `manifests` (par fin d'URL).
    private final class FakeNexus: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var requested: [String] = []
        private(set) var userAgents: [String] = []
        var manifests: [String: Fetcher.Response]

        init(manifests: [String: Fetcher.Response]) { self.manifests = manifests }

        func respond(_ request: URLRequest) -> Fetcher.Response {
            let url = request.url?.absoluteString ?? ""
            lock.withLock {
                requested.append(url)
                userAgents.append(request.value(forHTTPHeaderField: "User-Agent") ?? "")
            }
            if url.hasSuffix("/v2/graphql") {
                let json = #"{"data":{"modFiles":["#
                    + #"{"fileId":10,"version":"1.0.0","uri":"aa/bb/cc/aabbcc01-0000-4000-8000-000000000001","date":1700000000},"#
                    + #"{"fileId":11,"version":"1.1.0","uri":"aa/bb/cc/aabbcc02-0000-4000-8000-000000000002","date":1700000000},"#
                    + #"{"fileId":9,"version":"0.9.0","uri":"Old Mod 0.9-123-0-9-1580000000.zip","date":1580000000}"#
                    + "]}}"
                return .init(body: Data(json.utf8), status: 200)
            }
            let key = manifests.keys.first { url.hasSuffix($0) }
            return key.flatMap { manifests[$0] } ?? .init(body: nil, status: nil)
        }
    }

    private func manifest(_ path: String, _ sha: String) -> Fetcher.Response {
        let json = #"{"archive":{"hashes":{"SHA256":"ARCH"}},"files":[{"file_path":"\#(path)","file_hashes":{"SHA256":"\#(sha)"}}]}"#
        return .init(body: Data(json.utf8), status: 200)
    }

    private func fetch(_ nexus: FakeNexus, cache: URL?, now: Date = Date()) -> Fetcher.Outcome {
        Fetcher.fetch(modId: 123, cacheDirectory: cache, deadline: now.addingTimeInterval(20), now: now,
                      transport: { nexus.respond($0) })
    }

    @Test func readsRecentManifestsNewestFirstAndSkipsTheOldFormat() throws {
        let nexus = FakeNexus(manifests: ["000000000001": manifest("Mod/a.png", "AA"),
                                          "000000000002": manifest("Mod/a.png", "BB")])
        let outcome = fetch(nexus, cache: nil)
        #expect(outcome.files.map(\.fileId) == [11, 10])
        #expect(outcome.files.first?.manifest.files == ["Mod/a.png": "bb"])
        #expect(!outcome.incomplete)
        #expect(!nexus.requested.contains { $0.contains("Old") })
        #expect(nexus.userAgents.allSatisfy { $0.hasPrefix(NexusRequestBuilder.appName) })
    }

    @Test func aManifestIsCachedOnlyOnceDecoded() throws {
        let cache = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let nexus = FakeNexus(manifests: [
            "000000000001": manifest("Mod/a.png", "AA"),
            // 200 avec une page HTML : jamais mis en cache.
            "000000000002": .init(body: Data("<!doctype html>".utf8), status: 200),
        ])
        let first = fetch(nexus, cache: cache)
        #expect(first.files.map(\.fileId) == [10])
        #expect(first.incomplete)
        let cached = try FileManager.default.contentsOfDirectory(atPath: cache.path)
        #expect(cached == ["aa_bb_cc_aabbcc01-0000-4000-8000-000000000001.json"])

        nexus.manifests = [:]
        let second = fetch(nexus, cache: cache)
        #expect(second.files.map(\.fileId) == [10], "relu depuis le cache")
    }

    @Test func a404IsRememberedButNotForeverForARecentFile() throws {
        let cache = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let nexus = FakeNexus(manifests: ["000000000001": .init(body: Data("<html>".utf8), status: 404),
                                          "000000000002": .init(body: Data("<html>".utf8), status: 404)])
        let now = Date()
        let first = fetch(nexus, cache: cache, now: now)
        #expect(first.files.isEmpty)
        #expect(!first.incomplete, "un 404 dit qu'il n'y a rien, pas que la lecture a échoué")
        let marker = cache.appendingPathComponent("aa_bb_cc_aabbcc01-0000-4000-8000-000000000001.missing")
        #expect(FileManager.default.fileExists(atPath: marker.path))
        // Déposé hier : la marque ne vaut que 7 jours.
        let recent = Int(now.timeIntervalSince1970) - 86_400
        #expect(Fetcher.trustsMissingMarker(at: marker, fileDate: recent, now: now.addingTimeInterval(2 * 86_400)))
        #expect(!Fetcher.trustsMissingMarker(at: marker, fileDate: recent, now: now.addingTimeInterval(8 * 86_400)))
        // Déposé il y a plus d'un an : la marque vaut toujours.
        let old = Int(now.timeIntervalSince1970) - 400 * 86_400
        #expect(Fetcher.trustsMissingMarker(at: marker, fileDate: old, now: now.addingTimeInterval(800 * 86_400)))
    }

    @Test func noAnswerMeansIncompleteAndNothingCached() throws {
        let cache = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let outcome = fetch(FakeNexus(manifests: [:]), cache: cache)
        #expect(outcome.files.isEmpty)
        #expect(outcome.incomplete)
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).isEmpty)
    }

    @Test func aPassedDeadlineAsksNothing() {
        let nexus = FakeNexus(manifests: [:])
        let now = Date()
        let outcome = Fetcher.fetch(modId: 123, cacheDirectory: nil, deadline: now, now: now,
                                    transport: { nexus.respond($0) })
        #expect(outcome.incomplete)
        #expect(nexus.requested.isEmpty)
    }

    @Test func theFormatIsReadInTheUri() {
        #expect(Fetcher.ModFile(fileId: 1, version: "1", uri: "2f/0b/09/2f0b092f-2356-40ca-9fa0-de6a44e27c00", date: nil).isRecentFormat)
        #expect(!Fetcher.ModFile(fileId: 1, version: "1", uri: "ItemBags 3.1.0 (PC)-5382-3-1-0-1746473523.zip", date: nil).isRecentFormat)
    }
}
