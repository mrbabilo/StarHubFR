import Foundation
import Testing
@testable import StarHubTHCore

struct ModGroupPagesTests {
    private func mod(_ f: String, enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: "x.\(f)", name: f, folderName: f, version: "1", author: "", description: "",
                nexusUrl: "", nexusModId: "", isEnabled: enabled, dependencies: [], languages: [])
    }

    private func state(_ groups: [(String, [String])], collapsed: Set<String> = []) -> ModGroupsState {
        var s = ModGroupsState()
        for (name, folders) in groups {
            let id = try! s.createGroup(named: name).get()
            s.assign(folders, to: id)
            if collapsed.contains(name) { s.setCollapsed(group: id, true) }
        }
        return s
    }

    @Test func groupsFollowRankUngroupedLastEmptyHidden() {
        let s = state([("B", ["b1"]), ("A", ["a1"]), ("Empty", [])])
        let display = [mod("a1"), mod("z"), mod("b1", enabled: false)]
        let sections = ModGroupPages.sections(display: display, mode: .groups, state: s, category: { _ in nil })
        #expect(sections.map(\.title) == ["B", "A", nil])
        #expect(sections.map { $0.mods.map(\.folderName) } == [["b1"], ["a1"], ["z"]])
        #expect(sections[0].pausedCount == 1)
    }

    @Test func categoriesSortByNameUncategorizedLast() {
        let cats: [String: (Int, String)] = ["v": (4, "Visuels"), "a": (2, "Audio")]
        let sections = ModGroupPages.sections(display: [mod("v"), mod("n"), mod("a")], mode: .category,
                                              state: ModGroupsState(),
                                              category: { cats[$0.folderName].map { (id: $0.0, name: $0.1) } })
        #expect(sections.map(\.key) == [.category(2), .category(4), .uncategorized])
    }

    /// Review Focus 5 : la page 2 reprend « A (suite) » ; le groupe replié
    /// prend une place, ses mods aucune.
    @Test func twelveSlotsContinuationAndCollapsedCostOne() {
        let a = (1...14).map { "a\($0)" }
        let s = state([("A", a), ("Folded", ["f1", "f2"])], collapsed: ["Folded"])
        let display = (a + ["f1", "f2"]).map { mod($0) }
        let pages = ModGroupPages.pages(
            ModGroupPages.sections(display: display, mode: .groups, state: s, category: { _ in nil }), pageSize: 12)
        #expect(pages.count == 2)
        #expect(pages[0].map(\.mods.count) == [12])
        #expect(pages[1].map(\.continued) == [true, false])
        #expect(pages[1].map(\.mods.count) == [2, 0])
        #expect(ModGroupPages.page(of: "a13", in: pages) == 2)
        #expect(ModGroupPages.page(of: "f1", in: pages) == nil)
    }

    /// Review Focus 2 : on ne navigue ni ne sélectionne ce qu'on ne voit pas.
    @Test func navigationSkipsCollapsedGroups() {
        let s = state([("Open", ["o1"]), ("Folded", ["f1"])], collapsed: ["Folded"])
        let sections = ModGroupPages.sections(display: [mod("o1"), mod("f1"), mod("u")], mode: .groups,
                                              state: s, category: { _ in nil })
        #expect(ModGroupPages.navigationOrder(sections) == ["o1", "u"])
    }

    @Test func aFilterThatEmptiesAGroupHidesIt() {
        let s = state([("A", ["a1"]), ("B", ["b1"])])
        let sections = ModGroupPages.sections(display: [mod("b1")], mode: .groups, state: s, category: { _ in nil })
        #expect(sections.map(\.title) == ["B"])
    }

    @Test func aSectionStartingAtAPageBoundaryIsNotAContinuation() {
        let a = (1...12).map { "a\($0)" }
        let s = state([("A", a), ("B", ["b1"])])
        let pages = ModGroupPages.pages(ModGroupPages.sections(display: (a + ["b1"]).map { mod($0) },
                                                               mode: .groups, state: s, category: { _ in nil }),
                                        pageSize: 12)
        #expect(pages.count == 2)
        #expect(pages[1].map(\.continued) == [false])
    }

    /// Un bandeau replié **coûte** sa place : treize groupes repliés ne tiennent
    /// pas sur une page de douze (le sabotage `used += 0` ne rougissait rien).
    /// Revue finale, point 5 : le pied compte les mods des pages d'avant, pas
    /// `(page - 1) × 12` — un bandeau replié prend une place sans mod.
    @Test func modsBeforeAPageCountOnlyMods() {
        let s = state([("A", ["a1"]), ("B", ["b1"]), ("C", (1...20).map { "c\($0)" })], collapsed: ["A", "B"])
        let display = ["a1", "b1"].map { mod($0) } + (1...20).map { mod("c\($0)") }
        let pages = ModGroupPages.pages(
            ModGroupPages.sections(display: display, mode: .groups, state: s, category: { _ in nil }), pageSize: 12)
        #expect(ModGroupPages.modsBefore(page: 1, in: pages) == 0)
        #expect(ModGroupPages.modsBefore(page: 2, in: pages) == 10)
    }

    @Test func collapsedHeadersFillPagesToo() {
        let names = (1...13).map { "G\($0)" }
        let s = state(names.map { ($0, ["m\($0)"]) }, collapsed: Set(names))
        let display = names.map { mod("m\($0)") }
        let pages = ModGroupPages.pages(
            ModGroupPages.sections(display: display, mode: .groups, state: s, category: { _ in nil }), pageSize: 12)
        #expect(pages.map(\.count) == [12, 1])
    }
}
