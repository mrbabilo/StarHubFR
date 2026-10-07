import Testing
@testable import StarHubTHCore

/// I-T20 — la sélection multiple de la liste des mods : clic, ⌘clic,
/// ⇧clic, ⇧↑↓, ⌘A, et la règle d'Espace.
@Suite struct ModListSelectionTests {
    let order = ["A", "B", "C", "D", "E"]

    @Test func plainClickSelectsOnlyThatRowAndAnchorsIt() {
        var s = ModListSelection()
        s.click("B", kind: .toggle, in: order)
        s.click("D", kind: .plain, in: order)
        #expect(s.members(in: order) == ["D"])
        #expect(s.anchor == "D")
    }

    @Test func commandClickAddsThenRemoves() {
        var s = ModListSelection()
        s.click("A", kind: .plain, in: order)
        s.click("C", kind: .toggle, in: order)
        #expect(s.members(in: order) == ["A", "C"])
        s.click("A", kind: .toggle, in: order)
        #expect(s.members(in: order) == ["C"])
    }

    @Test func shiftClickSelectsTheRangeFromTheAnchorInBothDirections() {
        var s = ModListSelection()
        s.click("D", kind: .plain, in: order)
        s.click("B", kind: .extend, in: order)
        #expect(s.members(in: order) == ["B", "C", "D"])
        // L'ancre reste : un second ⇧clic redessine la plage depuis D.
        s.click("E", kind: .extend, in: order)
        #expect(s.members(in: order) == ["D", "E"])
        #expect(s.anchor == "D")
    }

    @Test func shiftClickWithoutAnAnchorInTheFramingActsAsAPlainClick() {
        var s = ModListSelection()
        s.click("Z", kind: .plain, in: ["Z"])          // ancre hors du cadrage courant
        s.click("C", kind: .extend, in: order)
        #expect(s.members(in: order) == ["C"])
        #expect(s.anchor == "C")
    }

    @Test func selectAllTakesTheWholeFramingAndClearEmptiesIt() {
        var s = ModListSelection()
        s.selectAll(order)
        #expect(s.members(in: order) == order)
        s.clear()
        #expect(s.members(in: order).isEmpty)
        #expect(s.anchor == nil)
    }

    @Test func membersFollowTheFramingOrderAndDropRowsFilteredOut() {
        var s = ModListSelection()
        s.click("E", kind: .plain, in: order)
        s.click("A", kind: .toggle, in: order)
        #expect(s.members(in: order) == ["A", "E"])
        #expect(s.members(in: ["B", "E"]) == ["E"])
    }

    private func mod(_ name: String, enabled: Bool) -> ModItem {
        ModItem(uniqueId: "a.\(name)", name: name, folderName: name, version: "1.0", author: "",
                description: "", nexusUrl: "", nexusModId: "", isEnabled: enabled,
                dependencies: [], children: nil, isGroup: false)
    }

    @Test func spaceEnablesWhenAnySelectedModIsPaused() {
        #expect(ModListSelection.spaceEnables([mod("A", enabled: true), mod("B", enabled: false)]))
        #expect(!ModListSelection.spaceEnables([mod("A", enabled: true), mod("B", enabled: true)]))
    }
}
