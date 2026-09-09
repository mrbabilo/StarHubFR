import Testing
import Foundation
@testable import StarHubTHCore

struct AppReleaseCheckTests {

    private let release = GitHubRelease(
        tagName: "v1.41.0", name: "Release v1.41.0",
        body: "Premier paragraphe visible.\n\nDeuxième paragraphe.",
        htmlURL: "https://github.com/mrbabilo/StarHubFR/releases/tag/v1.41.0")

    // MARK: - Décodage

    @Test func decodesGitHubJSONWithSnakeCase() throws {
        let json = """
        {"tag_name":"v1.41.0","name":"Release v1.41.0",
         "body":"notes","html_url":"https://example.com/r"}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(GitHubRelease.self, from: json)
        #expect(r.tagName == "v1.41.0")
        #expect(r.htmlURL == "https://example.com/r")
    }

    @Test func missingNameAndBodyDecodeAsNil() throws {
        let json = """
        {"tag_name":"v1.41.0","html_url":"https://example.com/r"}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(GitHubRelease.self, from: json)
        #expect(r.name == nil && r.body == nil)
    }

    @Test func missingTagNameFailsDecoding() {
        let json = #"{"html_url":"https://example.com/r"}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GitHubRelease.self, from: json)
        }
    }

    // MARK: - Politique

    private func decide(latest: GitHubRelease?, lastSeenTag: String? = nil,
                        lastCheckedAt: Date? = nil, bypass: Bool = false,
                        now: Date = Date(timeIntervalSince1970: 1_000_000)) -> AppReleaseDecision {
        AppReleasePolicy.decide(current: "1.40.0", latest: latest,
                                lastSeenTag: lastSeenTag, lastCheckedAt: lastCheckedAt,
                                now: now, bypassThrottle: bypass)
    }

    @Test func throttledWithinTtlUnlessBypassed() {
        let recent = Date(timeIntervalSince1970: 1_000_000 - 3600) // 1 h
        #expect(decide(latest: release, lastCheckedAt: recent) == .throttled)
        #expect(decide(latest: release, lastCheckedAt: recent, bypass: true)
                == .updateAvailable(release, alreadySeen: false))
    }

    @Test func checksWhenNeverCheckedOrTtlExpired() {
        #expect(decide(latest: release) != .throttled)
        let old = Date(timeIntervalSince1970: 1_000_000 - 25 * 3600) // 25 h
        #expect(decide(latest: release, lastCheckedAt: old) != .throttled)
    }

    @Test func noDataMeansUnavailable() {
        #expect(decide(latest: nil, bypass: true) == .unavailable)
    }

    @Test func newerTagMeansUpdateAvailable() {
        #expect(decide(latest: release, bypass: true)
                == .updateAvailable(release, alreadySeen: false))
    }

    @Test func sameAndOlderVersionsAreUpToDate() {
        let same = GitHubRelease(tagName: "v1.40.0", name: nil, body: nil,
                                 htmlURL: "https://example.com")
        let older = GitHubRelease(tagName: "1.39.9", name: nil, body: nil,
                                  htmlURL: "https://example.com")
        #expect(decide(latest: same, bypass: true) == .upToDate)
        #expect(decide(latest: older, bypass: true) == .upToDate)
    }

    @Test func seenTagIsReportedAsAlreadySeen() {
        #expect(decide(latest: release, lastSeenTag: "v1.41.0", bypass: true)
                == .updateAvailable(release, alreadySeen: true))
        #expect(decide(latest: release, lastSeenTag: "v1.40.0", bypass: true)
                == .updateAvailable(release, alreadySeen: false))
    }

    @Test func unparseableTagIsNotUpToDate() {
        let junk = GitHubRelease(tagName: "snapshot", name: nil, body: nil,
                                 htmlURL: "https://example.com")
        #expect(decide(latest: junk, bypass: true) == .unparseable)
    }

    // MARK: - Extrait de notes

    @Test func firstParagraphTakesFirstNonEmptyBlock() {
        #expect(AppReleasePolicy.firstParagraph(of: release.body)
                == "Premier paragraphe visible.")
        #expect(AppReleasePolicy.firstParagraph(of: nil) == nil)
        #expect(AppReleasePolicy.firstParagraph(of: "") == nil)
        #expect(AppReleasePolicy.firstParagraph(of: "\n\n\nTroisième position.") == "Troisième position.")
    }

    @Test func firstParagraphTruncatesWithEllipsis() {
        let long = String(repeating: "a", count: 400)
        let cut = AppReleasePolicy.firstParagraph(of: long, maxChars: 100)
        #expect(cut?.count == 101) // 100 + « … »
        #expect(cut?.hasSuffix("…") == true)
    }
}
