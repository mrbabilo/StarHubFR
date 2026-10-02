import Foundation
import Testing
@testable import StarHubTHCore

/// D1-T1 — les trois états de Profiler, lus dans la liste publiée par le
/// scan. Casse pliée, composants de packs compris.
@Suite struct ProfilerDetectionTests {

    private func mod(_ uid: String, folder: String? = nil, enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: uid, name: uid, folderName: folder ?? uid, version: "1.0.0",
                author: "A", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [], children: nil,
                isGroup: false, installedFileDate: nil)
    }

    @Test func absentWhenNothingMatches() {
        #expect(ProfilerDetection.resolve(mods: [mod("Other.Mod")]) == .absent)
        #expect(ProfilerDetection.resolve(mods: []) == .absent)
    }

    @Test func casingIsFolded() {
        #expect(ProfilerDetection.resolve(mods: [mod("SINZ.PROFILER")])
                == .enabled(folderName: "SINZ.PROFILER"))
    }

    @Test func pausedAndEnabledReadThePublishedState() {
        #expect(ProfilerDetection.resolve(mods: [mod("SinZ.Profiler", enabled: false)])
                == .paused(folderName: "SinZ.Profiler"))
        #expect(ProfilerDetection.resolve(mods: [mod("SinZ.Profiler")])
                == .enabled(folderName: "SinZ.Profiler"))
    }

    /// Un composant de pack compte comme un mod à part entière.
    @Test func packComponentsAreSeen() {
        let pack = ModItem(uniqueId: "", name: "Pack", folderName: "Pack", version: "",
                           author: "A", description: "", nexusUrl: "", nexusModId: "",
                           isEnabled: true, dependencies: [],
                           children: [mod("SinZ.Profiler", folder: "Pack/Profiler")],
                           isGroup: true, installedFileDate: nil)
        #expect(ProfilerDetection.resolve(mods: [pack])
                == .enabled(folderName: "Pack/Profiler"))
    }
}

