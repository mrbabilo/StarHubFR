import Foundation
import Testing
@testable import StarHubTHCore

/// Approbations et date de mise à jour par lots (GraphQL v2, sans clé).
@Suite struct NexusModStatsTests {

    /// Réponse réelle relevée le 2026-10-07 pour 1915, 3753, 48694 et un id
    /// inexistant (999999999) — absent de la réponse, sans erreur.
    static let realBatch = #"{"data":{"legacyModsByDomain":{"nodes":[{"modId":48694,"endorsements":11,"updatedAt":"2026-07-24T21:24:46Z"},{"modId":1915,"endorsements":489869,"updatedAt":"2026-04-16T11:18:42Z"},{"modId":3753,"endorsements":225648,"updatedAt":"2025-06-30T23:19:24Z"}]}}}"#

    @Test func decodesTheRealBatch() throws {
        let stats = try #require(NexusModStats.decode(Data(Self.realBatch.utf8)))
        #expect(stats.count == 3)
        #expect(stats[1915]?.endorsements == 489_869)
        #expect(stats[3753]?.updatedAt == ISO8601DateFormatter().date(from: "2025-06-30T23:19:24Z"))
        #expect(stats[999_999_999] == nil)
    }

    /// Réponse réelle du 2026-10-08, avec le champ `version` demandé pour le
    /// tri de la vérification directe : 44358 garde l'en-tête 1.0.0 alors
    /// que son fichier principal est en 1.0.1.
    @Test func decodesTheHeaderVersion() throws {
        let batch = #"{"data":{"legacyModsByDomain":{"nodes":[{"modId":44358,"endorsements":3,"updatedAt":"2026-04-07T09:55:13Z","version":"1.0.0"}]}}}"#
        let stats = try #require(NexusModStats.decode(Data(batch.utf8)))
        #expect(stats[44358]?.version == "1.0.0")
        #expect(NexusModStats.decode(Data(Self.realBatch.utf8))?[1915]?.version == nil)
        let body = try #require(NexusModStats.body(ids: [44358]))
        #expect(String(decoding: body, as: UTF8.self).contains("updatedAt version"))
    }

    @Test func serviceErrorsAreNotAnEmptyAnswer() {
        #expect(NexusModStats.decode(Data(#"{"errors":[{"message":"boom"}],"data":null}"#.utf8)) == nil)
        #expect(NexusModStats.decode(Data("<html>".utf8)) == nil)
    }

    @Test func batchesAreUniqueSortedAndCappedAt80() {
        let ids = Array((1...170).reversed()) + [5, 5, 0, -3]
        let batches = NexusModStats.batches(ids)
        #expect(batches.map(\.count) == [80, 80, 10])
        #expect(batches.first?.first == 1)
        #expect(batches.flatMap { $0 } == Array(1...170))
    }

    @Test func bodyAsksForEveryIdOfTheBatchWithTheMaxCount() throws {
        let body = try #require(NexusModStats.body(ids: [1915, 3753]))
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let variables = try #require(object["variables"] as? [String: Any])
        #expect(variables["c"] as? Int == 80)
        #expect((variables["ids"] as? [[String: Any]])?.count == 2)
        #expect((object["query"] as? String)?.contains("legacyModsByDomain") == true)
    }

    @Test func mergeUpdatesCountAndDateKeepsTheRestAndCreatesMissingEntries() {
        let old = NexusUpdateChecker.NexusModExtra(summary: "s", pictureUrl: "p", version: "1.0",
                                                     uploadedTime: Date(timeIntervalSince1970: 1))
        let fresh = Date(timeIntervalSince1970: 2_000_000_000)
        let merged = NexusModStats.merge([1915: .init(endorsements: 9, updatedAt: fresh),
                                          42: .init(endorsements: 3, updatedAt: nil)],
                                         into: ["1915": old, "7": old])
        #expect(merged["1915"]?.summary == "s")
        #expect(merged["1915"]?.endorsements == 9)
        #expect(merged["1915"]?.uploadedTime == fresh)
        #expect(merged["7"] == old)                      // absent du lot : intact
        #expect(merged["42"]?.endorsements == 3)
        #expect(merged["42"]?.summary == "")
    }

    @Test func refreshIsDueAfterADayOrWhenNeverDone() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(NexusModStats.isDue(lastRefresh: nil, now: now))
        #expect(!NexusModStats.isDue(lastRefresh: now.addingTimeInterval(-3_600), now: now))
        #expect(NexusModStats.isDue(lastRefresh: now.addingTimeInterval(-90_000), now: now))
    }
}
