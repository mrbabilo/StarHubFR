import Testing
import Foundation
@testable import StarHubTHCore

/// Locks the contract of `ModManifest.parseNexusId(fromUpdateKeys:)`, the
/// shared helper used by both `ZipModInfo.init` (zip analysis) and
/// `StarHubTHViewModel.parseModFolder` (live mod scan). Before this helper
/// existed the same parsing was duplicated in both places; these tests
/// guarantee future changes only need to be made once.
struct ParseNexusIdTests {

    @Test func parsesPlainNexusKey() {
        let r = ModManifest.parseNexusId(fromUpdateKeys: ["nexus:191"])
        #expect(r?.id == "191")
        #expect(r?.url == "https://www.nexusmods.com/stardewvalley/mods/191")
    }

    @Test func ignoresCaseAndWhitespace() {
        let r = ModManifest.parseNexusId(fromUpdateKeys: ["  Nexus:   240  "])
        #expect(r?.id == "240")
    }

    @Test func dropsVariantSuffix() {
        // Multi-mod pack convention — `Nexus:<id>@<variant>`. The helper must
        // collapse all variants onto the same canonical id.
        let r = ModManifest.parseNexusId(fromUpdateKeys: ["Nexus:23169@SwimItems"])
        #expect(r?.id == "23169")
    }

    @Test func returnsFirstValidKeyWhenManyPresent() {
        let keys = ["github:foo", "nexus:notanumber", "nexus:100", "nexus:200"]
        let r = ModManifest.parseNexusId(fromUpdateKeys: keys)
        #expect(r?.id == "100")
    }

    @Test func rejectsZeroAndNegativeIds() {
        #expect(ModManifest.parseNexusId(fromUpdateKeys: ["nexus:0"]) == nil)
        #expect(ModManifest.parseNexusId(fromUpdateKeys: ["nexus:-5"]) == nil)
    }

    @Test func returnsNilForEmptyOrNullInput() {
        #expect(ModManifest.parseNexusId(fromUpdateKeys: nil) == nil)
        #expect(ModManifest.parseNexusId(fromUpdateKeys: []) == nil)
        #expect(ModManifest.parseNexusId(fromUpdateKeys: ["github:foo"]) == nil)
    }
}
