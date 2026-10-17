import Testing
@testable import StarHubTHCore

/// P5-6a — actifs d'abord, mods en pause à part, ordre gardé.
struct NexusUpdateGroupsTests {

    @Test func activeAndPausedKeepTheirArrivalOrder() {
        let state: [String: Bool] = ["a": false, "b": true, "c": false, "d": true]
        let groups = NexusUpdateGroups(["a", "b", "c", "d"]) { state[$0] }
        #expect(groups.active == ["b", "d"])
        #expect(groups.paused == ["a", "c"])
    }

    /// Introuvable sur le disque : rien n'est chargé, il ne passe pas devant.
    @Test func aModNotFoundOnDiskCountsAsPaused() {
        let groups = NexusUpdateGroups(["gone"]) { _ in nil }
        #expect(groups.active.isEmpty)
        #expect(groups.paused == ["gone"])
    }
}
