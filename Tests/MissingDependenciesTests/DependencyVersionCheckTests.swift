import Foundation
import Testing
@testable import StarHubTHCore

/// Une archive qui livre un mod plus ancien que ce qu'exige un mod actif
/// (relevé des sources du 2026-11-11). Cas réel du parc : StardewUI, fork
/// `0.6.4-unofficial-mushymato.1` installé, original abandonné en 0.6.1.
@Suite struct DependencyVersionCheckTests {

    private func mod(_ uid: String, _ name: String, enabled: Bool = true,
                     needs: [(String, String?, Bool)] = []) -> ModItem {
        ModItem(uniqueId: uid, name: name, folderName: uid, version: "1.0.0",
                author: "A", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled,
                dependencies: needs.map { ModDependency(uniqueId: $0.0, isRequired: $0.2, minimumVersion: $0.1) })
    }

    private let ui = "focustense.StardewUI"
    private var park: [ModItem] {
        [mod("a.Bazaar", "Livestock Bazaar", needs: [(ui, "0.6.3-unofficial-mushymato.1", true)]),
         mod("a.Panel", "Machine Control Panel", needs: [(ui, "0.6.4-unofficial-mushymato.0", true)]),
         mod("a.Hub", "Hotkey Hub", needs: [(ui, "0.6.1", true)]),
         mod("a.Journal", "Quest Journal", needs: [(ui, nil, true)])]
    }

    @Test func theOriginalIsTooOldForTheMostDemandingMod() {
        let unmet = DependencyVersionCheck.unmet(detected: [(ui, "StardewUI", "0.6.1")], mods: park)
        #expect(unmet.count == 1)
        #expect(unmet.first?.required == "0.6.4-unofficial-mushymato.0")
        #expect(unmet.first?.requiredBy == "Machine Control Panel")
        #expect(unmet.first?.found == "0.6.1")
    }

    @Test func theForkSatisfiesEveryone() {
        #expect(DependencyVersionCheck.unmet(detected: [(ui, "StardewUI", "0.6.4-unofficial-mushymato.1")],
                                             mods: park).isEmpty)
        // Casse ignorée, comme SMAPI.
        #expect(DependencyVersionCheck.unmet(detected: [("FOCUSTENSE.STARDEWUI", "StardewUI", "0.6.4-unofficial-mushymato.1")],
                                             mods: park).isEmpty)
    }

    /// Un mod en pause, une dépendance optionnelle, un mod livré dans la même
    /// archive : aucun n'exige rien.
    @Test func onlyRequiredDependenciesOfActiveModsOutsideTheArchiveCount() {
        let mods = [mod("a.Paused", "Paused", enabled: false, needs: [(ui, "9.0.0", true)]),
                    mod("a.Optional", "Optional", needs: [(ui, "9.0.0", false)]),
                    mod("a.Shipped", "Shipped", needs: [(ui, "9.0.0", true)])]
        #expect(DependencyVersionCheck.unmet(detected: [(ui, "StardewUI", "0.6.1"), ("a.Shipped", "Shipped", "2.0.0")],
                                             mods: mods).isEmpty)
    }

    // MARK: - Lecture du manifeste

    @Test func theParserReadsMinimumVersionAndKeepsTheHighest() {
        let deps = ModDependencyParser.parse(manifest: [
            "Dependencies": [["UniqueID": ui, "MinimumVersion": "0.6.1"],
                             ["UniqueID": "FOCUSTENSE.StardewUI", "MinimumVersion": "0.6.4-unofficial-mushymato.0", "IsRequired": false],
                             ["UniqueID": "other.Mod", "MinimumVersion": ""]],
            "ContentPackFor": ["UniqueID": "Pathoschild.ContentPatcher", "MinimumVersion": "2.0.0"],
        ])
        #expect(deps.count == 3)
        #expect(deps.first { $0.uniqueId == ui }?.minimumVersion == "0.6.4-unofficial-mushymato.0")
        #expect(deps.first { $0.uniqueId == ui }?.isRequired == true)
        #expect(deps.first { $0.uniqueId == "other.Mod" }?.minimumVersion == nil)
        #expect(deps.first { $0.uniqueId == "Pathoschild.ContentPatcher" }?.minimumVersion == "2.0.0")
    }
}
