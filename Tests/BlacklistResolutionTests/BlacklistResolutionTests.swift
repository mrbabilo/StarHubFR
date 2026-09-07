import Testing
import Foundation
@testable import StarHubTHCore

struct BlacklistResolutionTests {
    private func mod(_ folder: String, id: String, enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: id, name: folder, folderName: folder, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [], languages: [])
    }

    private func pack(_ folder: String, children: [ModItem]) -> ModItem {
        var group = mod(folder, id: "")
        group.children = children
        group.isGroup = true
        return group
    }

    @Test func aBlacklistedModContributesItsOwnIdentifier() {
        let result = BlacklistResolution.profileIds(
            blacklist: ["SpaceCore"], in: [mod("SpaceCore", id: "spacechase0.SpaceCore")])
        #expect(result.ids == ["spacechase0.SpaceCore"])
        #expect(result.unresolved.isEmpty)
    }

    @Test func aBlacklistedPackContributesEveryComponent() {
        let sve = pack("SVE", children: [mod("SVE/Core", id: "FlashShifter.SVE"),
                                         mod("SVE/Extra", id: "FlashShifter.SVEExtra")])
        let result = BlacklistResolution.profileIds(blacklist: ["SVE"], in: [sve])
        #expect(result.ids == ["FlashShifter.SVE", "FlashShifter.SVEExtra"])
        #expect(result.unresolved.isEmpty)
    }

    @Test func aBlacklistedModThatIsNoLongerInstalledIsReported() {
        let result = BlacklistResolution.profileIds(
            blacklist: ["Gone", "SpaceCore"], in: [mod("SpaceCore", id: "spacechase0.SpaceCore")])
        #expect(result.ids == ["spacechase0.SpaceCore"])
        #expect(result.unresolved == ["Gone"])
    }

    @Test func aModWithoutAnIdentifierIsReportedRatherThanDropped() {
        let result = BlacklistResolution.profileIds(blacklist: ["Nameless"],
                                                   in: [mod("Nameless", id: "")])
        #expect(result.ids.isEmpty)
        #expect(result.unresolved == ["Nameless"])
    }

    @Test func aPackWithNoUsableComponentIsReported() {
        let empty = pack("Broken", children: [mod("Broken/A", id: ""), mod("Broken/B", id: "")])
        let result = BlacklistResolution.profileIds(blacklist: ["Broken"], in: [empty])
        #expect(result.ids.isEmpty)
        #expect(result.unresolved == ["Broken"])
    }

    @Test func aPartlyIdentifiedPackContributesWhatItCan() {
        let half = pack("Half", children: [mod("Half/A", id: "author.A"), mod("Half/B", id: "")])
        let result = BlacklistResolution.profileIds(blacklist: ["Half"], in: [half])
        #expect(result.ids == ["author.A"])
        #expect(result.unresolved.isEmpty)
    }

    @Test func aModAlreadyInTheProfileIsNotAddedTwice() {
        let result = BlacklistResolution.profileIds(
            blacklist: ["SpaceCore"], in: [mod("SpaceCore", id: "spacechase0.SpaceCore")],
            existing: ["spacechase0.SpaceCore"])
        #expect(result.ids.isEmpty)
        #expect(result.unresolved.isEmpty)
    }

    @Test func deduplicationIgnoresCase() {
        let result = BlacklistResolution.profileIds(
            blacklist: ["SpaceCore"], in: [mod("SpaceCore", id: "spacechase0.SpaceCore")],
            existing: ["SPACECHASE0.SPACECORE"])
        #expect(result.ids.isEmpty)
    }

    @Test func twoBlacklistedModsSharingAnIdentifierContributeItOnce() {
        let mods = [mod("CopyA", id: "shared.Id"), mod("CopyB", id: "shared.Id")]
        let result = BlacklistResolution.profileIds(blacklist: ["CopyA", "CopyB"], in: mods)
        #expect(result.ids == ["shared.Id"])
    }

    @Test func theResultIsOrderedByBlacklistedName() {
        let mods = [mod("Zulu", id: "z.Id"), mod("Alpha", id: "a.Id"), mod("Mike", id: "m.Id")]
        let result = BlacklistResolution.profileIds(blacklist: ["Zulu", "Alpha", "Mike"], in: mods)
        #expect(result.ids == ["a.Id", "m.Id", "z.Id"])
    }

    @Test func noBlacklistedModsResolvesToNothingAtAll() {
        let result = BlacklistResolution.profileIds(blacklist: [], in: [mod("A", id: "a")])
        #expect(result.ids.isEmpty)
        #expect(result.unresolved.isEmpty)
    }

    @Test func aPausedModIsStillResolvable() {
        let result = BlacklistResolution.profileIds(
            blacklist: ["Sleeping"], in: [mod("Sleeping", id: "some.Id", enabled: false)])
        #expect(result.ids == ["some.Id"])
    }
}