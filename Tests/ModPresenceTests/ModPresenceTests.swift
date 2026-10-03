import Foundation
import Testing
@testable import StarHubTHCore

/// Les trois états d'un mod (la sonde, Profiler), lus dans la liste publiée
/// par le scan. Casse pliée, composants de packs compris.
@Suite struct ModPresenceTests {

    private func mod(_ uid: String, folder: String? = nil, enabled: Bool = true,
                     version: String = "1.0.0") -> ModItem {
        ModItem(uniqueId: uid, name: uid, folderName: folder ?? uid, version: version,
                author: "A", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [], children: nil,
                isGroup: false, installedFileDate: nil)
    }

    @Test func absentWhenNothingMatches() {
        #expect(ModPresence.resolve(uniqueId: ModPresence.probeId, in: [mod("Other.Mod")]) == .absent)
        #expect(ModPresence.resolve(uniqueId: ModPresence.probeId, in: []) == .absent)
    }

    @Test func casingIsFolded() {
        #expect(ModPresence.resolve(uniqueId: ModPresence.profilerId, in: [mod("SINZ.PROFILER")])
                == .enabled(folderName: "SINZ.PROFILER", version: "1.0.0"))
    }

    @Test func pausedAndEnabledReadThePublishedStateAndVersion() {
        let probe = ModPresence.probeId
        #expect(ModPresence.resolve(uniqueId: probe, in: [mod(probe, enabled: false, version: "0.9.0")])
                == .paused(folderName: probe, version: "0.9.0"))
        #expect(ModPresence.resolve(uniqueId: probe, in: [mod(probe, version: "0.9.0")])
                == .enabled(folderName: probe, version: "0.9.0"))
    }

    /// Un composant de pack compte comme un mod à part entière.
    @Test func packComponentsAreSeen() {
        let pack = ModItem(uniqueId: "", name: "Pack", folderName: "Pack", version: "",
                           author: "A", description: "", nexusUrl: "", nexusModId: "",
                           isEnabled: true, dependencies: [],
                           children: [mod("SinZ.Profiler", folder: "Pack/Profiler")],
                           isGroup: true, installedFileDate: nil)
        #expect(ModPresence.resolve(uniqueId: ModPresence.profilerId, in: [pack])
                == .enabled(folderName: "Pack/Profiler", version: "1.0.0"))
        #expect(ModPresence.resolve(uniqueId: ModPresence.profilerId, in: [pack]).folderName == "Pack/Profiler")
    }
}
