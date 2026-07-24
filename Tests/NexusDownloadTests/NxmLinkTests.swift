import Testing
import Foundation
@testable import StarHubTHCore

struct NxmLinkTests {
    @Test func parsesFullFreeUserLink() {
        let url = URL(string: "nxm://stardewvalley/mods/41318/files/174232?key=abc123&expires=1666593200&user_id=42")!
        let link = NxmLink.parse(url)
        #expect(link?.gameDomain == "stardewvalley")
        #expect(link?.modId == 41318)
        #expect(link?.fileId == 174232)
        #expect(link?.key == "abc123")
        #expect(link?.expires == 1666593200)
        #expect(link?.userId == 42)
    }

    @Test func parsesPremiumLinkWithoutKey() {
        let url = URL(string: "nxm://stardewvalley/mods/41318/files/174232")!
        let link = NxmLink.parse(url)
        #expect(link?.modId == 41318)
        #expect(link?.fileId == 174232)
        #expect(link?.key == nil)
        #expect(link?.expires == nil)
    }

    @Test func rejectsWrongScheme() {
        #expect(NxmLink.parse(URL(string: "https://stardewvalley/mods/1/files/2")!) == nil)
    }

    @Test func rejectsMalformedPath() {
        #expect(NxmLink.parse(URL(string: "nxm://stardewvalley/mods/41318")!) == nil)
        #expect(NxmLink.parse(URL(string: "nxm://stardewvalley/mods/abc/files/xyz")!) == nil)
    }

    @Test func rejectsWrongPathKeywords() {
        #expect(NxmLink.parse(URL(string: "nxm://stardewvalley/foo/41318/bar/174232")!) == nil)
    }

    @Test func rejectsEmptyHost() {
        #expect(NxmLink.parse(URL(string: "nxm:///mods/41318/files/174232")!) == nil)
    }
}
