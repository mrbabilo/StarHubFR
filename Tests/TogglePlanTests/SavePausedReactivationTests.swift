import Foundation
import Testing
@testable import StarHubTHCore

/// P5-8 — « Réactiver ces mods » depuis une partie : dossiers de tête, packs
/// entiers, dépendances requises en pause si le chaînage est actif.
@Suite struct SavePausedReactivationTests {

    private func mod(_ name: String, id: String, enabled: Bool = false,
                     deps: [ModDependency] = [], isGroup: Bool = false,
                     children: [ModItem]? = nil, folderName: String? = nil) -> ModItem {
        ModItem(uniqueId: id, name: name, folderName: folderName ?? name, version: "1.0", author: "T",
                description: "", nexusUrl: "", nexusModId: "", updateKeys: [], isEnabled: enabled,
                dependencies: deps, children: children, isGroup: isGroup)
    }

    private func footprint(_ folder: String) -> PausedModFootprint {
        PausedModFootprint(folderName: folder, name: folder, counts: FingerprintCounts(objects: 1))
    }

    /// Deux composants du même pack : le pack une fois, compté comme entier.
    @Test func componentsWakeTheirPackOnce() {
        let farm = mod("Farm", id: "sve.farm", folderName: "SVE/Farm")
        let town = mod("Town", id: "sve.town", folderName: "SVE/Town")
        let pack = mod("SVE", id: "", isGroup: true, children: [farm, town])
        let plan = SavePausedReactivation(footprints: [footprint("SVE/Farm"), footprint("SVE/Town")],
                                          mods: [pack], chain: false)
        #expect(plan.mods.map(\.folderName) == ["SVE"])
        #expect(plan.wholePacks == 1)
    }

    /// Chaînage actif : la dépendance requise en pause suit le mod ; sans
    /// chaînage, seul le mod de la section bouge.
    @Test func requiredPausedDependenciesFollowWhenChaining() {
        let core = mod("Core", id: "core")
        let tea = mod("Tea", id: "tea", deps: [ModDependency(uniqueId: "core", isRequired: true)])
        let chained = SavePausedReactivation(footprints: [footprint("Tea")], mods: [tea, core], chain: true)
        #expect(chained.mods.map(\.folderName) == ["Tea", "Core"])
        let alone = SavePausedReactivation(footprints: [footprint("Tea")], mods: [tea, core], chain: false)
        #expect(alone.mods.map(\.folderName) == ["Tea"])
    }

    /// Un mod déjà actif, ou que le parc n'a plus, ne s'ajoute pas ; une
    /// dépendance partagée ne compte qu'une fois.
    @Test func activeUnknownAndSharedAreNotRepeated() {
        let core = mod("Core", id: "core")
        let dep = [ModDependency(uniqueId: "core", isRequired: true)]
        let tea = mod("Tea", id: "tea", deps: dep)
        let swim = mod("Swim", id: "swim", deps: dep)
        let live = mod("Live", id: "live", enabled: true)
        let plan = SavePausedReactivation(
            footprints: [footprint("Tea"), footprint("Live"), footprint("Gone"), footprint("Swim")],
            mods: [tea, swim, core, live], chain: true)
        #expect(plan.mods.map(\.folderName) == ["Tea", "Core", "Swim"])
        #expect(plan.wholePacks == 0)
    }
}
