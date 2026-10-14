import Foundation
import Testing
@testable import StarHubTHCore

struct ModGroupsStateTests {
    @Test func namesAreRequiredAndUniqueIgnoringCase() throws {
        var state = ModGroupsState()
        #expect(state.createGroup(named: "  ") == .failure(.empty))
        let npc = try state.createGroup(named: "PNJ").get()
        #expect(state.createGroup(named: "pnj") == .failure(.taken))
        #expect(state.rename(npc, to: " Pnj ") == nil)        // lui-même : permis
        #expect(state.groups.map(\.name) == ["Pnj"])
        let other = try state.createGroup(named: "Visuels").get()
        #expect(state.rename(other, to: "PNJ") == .taken)
    }

    @Test func oneGroupPerModAndDeletingFreesMembers() throws {
        var state = ModGroupsState()
        let a = try state.createGroup(named: "A").get()
        let b = try state.createGroup(named: "B").get()
        state.assign(["SVE", "RSV"], to: a)
        state.assign(["SVE"], to: b)
        #expect(state.group(of: "SVE")?.id == b)
        #expect(state.group(of: "RSV")?.id == a)
        state.deleteGroup(a)
        #expect(state.group(of: "RSV") == nil)
        #expect(state.groups.map(\.id) == [b])
        state.assign(["SVE"], to: nil)
        #expect(state.membership.isEmpty)
    }

    @Test func moveClampsAtBothEnds() throws {
        var state = ModGroupsState()
        let a = try state.createGroup(named: "A").get()
        let b = try state.createGroup(named: "B").get()
        state.move(b, by: -5)
        #expect(state.groups.map(\.id) == [b, a])
        state.move(b, by: 9)
        #expect(state.groups.map(\.id) == [a, b])
    }

    /// Review Focus 3.
    @Test func renameMigratesOrCopiesWhenTheOldNameIsShared() throws {
        var state = ModGroupsState()
        let a = try state.createGroup(named: "A").get()
        state.assign(["Old"], to: a)
        state.migrate(from: "Old", to: "New", shared: false)
        #expect(state.group(of: "Old") == nil && state.group(of: "New")?.id == a)
        state.migrate(from: "New", to: "Newer", shared: true)
        #expect(state.group(of: "New")?.id == a && state.group(of: "Newer")?.id == a)
        state.purge("Newer")
        #expect(state.group(of: "Newer") == nil)
    }

    @Test func assigningToAnUnknownGroupDoesNothing() {
        var state = ModGroupsState()
        state.assign(["X"], to: UUID())
        #expect(state.membership.isEmpty)
    }

    @Test func aFileFromAnotherVersionStillDecodes() throws {
        let older = #"{"groups":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"A"}]}"#
        let state = try JSONDecoder().decode(ModGroupsState.self, from: Data(older.utf8))
        #expect(state.groups.map(\.name) == ["A"] && state.groups[0].collapsed == false)
        let newer = #"{"groups":[],"membership":{},"collapsedCategories":[],"colors":{}}"#
        #expect(try JSONDecoder().decode(ModGroupsState.self, from: Data(newer.utf8)) == ModGroupsState())
    }
}
