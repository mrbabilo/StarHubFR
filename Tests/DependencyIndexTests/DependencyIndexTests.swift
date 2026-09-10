import Foundation
import Testing
@testable import StarHubTHCore

/// Les index dérivés du parc (REFACTORING §6, domaine Dépendances) :
/// aplatissage packs/simples, pli de casse des UniqueIDs, doublons sortis
/// du même parcours, requêtes manquant/désactivé, et l'union des racines
/// d'un pack.
@Suite struct DependencyIndexTests {

    private func mod(_ name: String, id: String, enabled: Bool = true,
                     deps: [ModDependency] = [], isGroup: Bool = false,
                     children: [ModItem]? = nil, folderName: String? = nil) -> ModItem {
        ModItem(
            uniqueId: id,
            name: name,
            folderName: folderName ?? name,
            version: "1.0",
            author: "T",
            description: "",
            nexusUrl: "",
            nexusModId: "",
            updateKeys: [],
            isEnabled: enabled,
            dependencies: deps,
            children: children,
            isGroup: isGroup)
    }

    private func dep(_ id: String, required: Bool = true) -> ModDependency {
        ModDependency(uniqueId: id, isRequired: required)
    }

    // MARK: - Construction

    /// Packs aplatis : les composants portent le `folderName` du pack
    /// (`Pack/Enfant`) — c'est lui qui distingue « Swim » de
    /// « Swim Mod-23169…/Swim ».
    @Test func buildFlattensGroupsAndFoldsCase() {
        let child = mod("Swim", id: "swim.SwimMod", folderName: "Swim Mod-23169/Swim")
        let pack = mod("Swim Pack", id: "", isGroup: true, children: [child])
        let plain = mod("Cheats", id: "CJB.CheatsMenu")
        let index = DependencyIndex.build(from: [pack, plain])

        #expect(index.installedUniqueIds == ["swim.swimmod", "cjb.cheatsmenu"])
        #expect(index.installedModsByUniqueId["swim.swimmod"]?.folderName == "Swim Mod-23169/Swim")
        #expect(index.installedModStates["cjb.cheatsmenu"] == true)
    }

    /// Les doublons sortent du même parcours que les index : deux mods au
    /// même UniqueID (activé + en pause) doivent être vus, là où les
    /// dictionnaires en écrasent un sur deux.
    @Test func duplicateIndexSeesWhatMapsCrush() {
        let enabled = mod("Swim", id: "swim.Swim", folderName: "Swim")
        let paused = mod("Swim copy", id: "swim.Swim", enabled: false, folderName: ".Swim copy")
        let index = DependencyIndex.build(from: [enabled, paused])
        #expect(index.duplicateIndex != .empty)
    }

    // MARK: - Requêtes

    @Test func missingAndDisabledQueries() {
        let installed = mod("Dep", id: "dep.present")
        let disabledDep = mod("Off", id: "dep.off", enabled: false)
        let index = DependencyIndex.build(from: [installed, disabledDep])
        let mod = mod("Needs", id: "needs", deps: [dep("dep.present"), dep("dep.missing"), dep("dep.off")])

        #expect(index.missing(for: mod) == ["dep.missing"])
        #expect(index.disabled(for: mod) == ["dep.off"])
    }

    // MARK: - Union des racines d'un pack

    /// Déduplication par UniqueID plié, et escalade : une dépendance
    /// **optionnelle en premier** devient requise si un autre enfant
    /// l'exige — l'ordre des enfants ne doit pas affaiblir le pack.
    @Test func mergedPackRootsDedupAndEscalate() {
        let a = mod("A", id: "pack.A", deps: [dep("shared.Dep", required: false), dep("a.only", required: false)])
        let b = mod("B", id: "pack.B", deps: [dep("Shared.dep"), dep("b.only")])
        let pack = mod("Pack", id: "", isGroup: true, children: [a, b])

        let roots = DependencyIndex.mergedPackRoots(of: pack)
        #expect(roots.count == 3)
        let shared = try! #require(roots.first { $0.uniqueId.lowercased() == "shared.dep" })
        #expect(shared.isRequired)
        #expect(roots.contains { $0.uniqueId.lowercased() == "a.only" && !$0.isRequired })
        #expect(roots.contains { $0.uniqueId.lowercased() == "b.only" && $0.isRequired })
    }

    /// Un mod simple rend ses propres dépendances — pas d'union.
    @Test func plainModKeepsItsOwnRoots() {
        let mod = mod("Solo", id: "solo", deps: [dep("solo.dep")])
        #expect(DependencyIndex.mergedPackRoots(of: mod).count == 1)
    }

    // MARK: - Résolution de l'arbre

    /// La résolution passe par le pli de casse : une dépendance écrite
    /// `DEP.PRESENT` rencontre le mod installé sous `dep.present`.
    @Test func resolveFoldsCase() {
        let installed = mod("Dep", id: "dep.present", deps: [])
        let index = DependencyIndex.build(from: [installed])
        #expect(index.resolve("DEP.PRESENT")?.mod.uniqueId == "dep.present")
        #expect(index.resolve("dep.absent") == nil)
    }
}
