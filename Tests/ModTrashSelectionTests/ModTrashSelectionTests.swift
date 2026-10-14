import Testing
@testable import StarHubTHCore

struct ModTrashSelectionTests {
    private func mod(_ folder: String, id: String, enabled: Bool = true, requires: [String] = [],
                     optional: [String] = []) -> ModItem {
        ModItem(uniqueId: id, name: folder, folderName: folder, version: "1.0", author: "", description: "",
                nexusUrl: "", nexusModId: "", isEnabled: enabled,
                dependencies: requires.map { ModDependency(uniqueId: $0, isRequired: true) }
                    + optional.map { ModDependency(uniqueId: $0, isRequired: false) },
                languages: [])
    }

    private func pack(_ folder: String, _ children: [ModItem], enabled: Bool = true) -> ModItem {
        var head = mod(folder, id: "", enabled: enabled)
        head.isGroup = true
        head.children = children
        return head
    }

    @Test func anActiveDependentOutsideTheSelectionIsNamed() {
        let cp = mod("ContentPatcher", id: "Pathoschild.ContentPatcher")
        let sve = mod("[CP] SVE", id: "FlashShifter.SVE", requires: ["pathoschild.contentpatcher"])
        let plan = ModTrashSelection.plan(selected: [cp], all: [cp, sve])
        #expect(plan.trashable.map(\.folderName) == ["ContentPatcher"])
        #expect(plan.dependents == ["[CP] SVE"])
    }

    @Test func aDependentThatLeavesWithTheSelectionIsNotNamed() {
        let cp = mod("ContentPatcher", id: "Pathoschild.ContentPatcher")
        let sve = mod("[CP] SVE", id: "FlashShifter.SVE", requires: ["Pathoschild.ContentPatcher"])
        #expect(ModTrashSelection.plan(selected: [cp, sve], all: [cp, sve]).dependents.isEmpty)
    }

    @Test func pausedAndOptionalDependentsAreIgnored() {
        let cp = mod("ContentPatcher", id: "Pathoschild.ContentPatcher")
        let paused = mod("Paused", id: "x.paused", enabled: false, requires: ["Pathoschild.ContentPatcher"])
        let optional = mod("Optional", id: "x.optional", optional: ["Pathoschild.ContentPatcher"])
        #expect(ModTrashSelection.plan(selected: [cp], all: [cp, paused, optional]).dependents.isEmpty)
    }

    /// Review Focus 1 — un pack sélectionné porte les identifiants de ses
    /// composants ; un dépendant **dans** un autre pack est nommé par son nom.
    @Test func packComponentsCountOnBothSides() {
        let framework = pack("RidgesideVillage", [mod("RidgesideVillage/RSV", id: "Rafseazz.RSV")])
        let user = pack("Addon", [mod("Addon/Part", id: "y.part", requires: ["rafseazz.rsv"])])
        let flat = mod("Flat", id: "z.flat")
        let plan = ModTrashSelection.plan(selected: [framework, flat], all: [framework, user, flat])
        #expect(plan.trashable.map(\.folderName) == ["RidgesideVillage", "Flat"])
        #expect(plan.dependents == ["Addon/Part"])
    }

    @Test func probeAndSmapiModsAreRefusedNotTrashed() {
        let probe = mod("StarHubFR Probe", id: "mrbabilo.StarHubFR.Probe")
        let console = mod("ConsoleCommands", id: "SMAPI.ConsoleCommands")
        let other = mod("Other", id: "x.other")
        let plan = ModTrashSelection.plan(selected: [probe, console, other], all: [probe, console, other])
        #expect(plan.trashable.map(\.folderName) == ["Other"])
        #expect(plan.refused == [.init(name: "StarHubFR Probe", reason: .probe),
                                 .init(name: "ConsoleCommands", reason: .smapiBundled)])
    }

    @Test func emptySelectionAndDuplicateDependentsCollapse() {
        #expect(ModTrashSelection.plan(selected: [], all: []).trashable.isEmpty)
        let a = mod("A", id: "x.a")
        let b = mod("B", id: "x.b")
        let both = mod("Both", id: "x.both", requires: ["x.a", "x.b"])
        #expect(ModTrashSelection.plan(selected: [a, b], all: [a, b, both]).dependents == ["Both"])
    }
}
