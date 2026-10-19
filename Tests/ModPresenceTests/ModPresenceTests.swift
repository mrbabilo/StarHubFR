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

    @Test func anAbsentOrPausedProbeNeedsTheActionCard() {
        #expect(PerformanceProbePresentation.showsActionCard(
            presence: .absent, bundledVersion: nil))
        #expect(PerformanceProbePresentation.showsActionCard(
            presence: .paused(folderName: "Probe", version: "0.9.28"),
            bundledVersion: "0.9.28"))
    }

    @Test func anOutdatedOrUpgradeableProbeNeedsTheActionCard() {
        #expect(PerformanceProbePresentation.showsActionCard(
            presence: .enabled(folderName: "Probe", version: "0.4.13"),
            bundledVersion: "0.9.28"))
        #expect(PerformanceProbePresentation.showsActionCard(
            presence: .enabled(folderName: "Probe", version: "0.9.24"),
            bundledVersion: "0.9.24"))
        #expect(PerformanceProbePresentation.showsActionCard(
            presence: .enabled(folderName: "Probe", version: "0.9.25"),
            bundledVersion: "0.9.28"))
    }

    @Test func aCurrentProbeUsesOnlyTheCompactStatusAndSettings() {
        #expect(!PerformanceProbePresentation.showsActionCard(
            presence: .enabled(folderName: "Probe", version: "0.9.28"),
            bundledVersion: "0.9.28"))
        #expect(!PerformanceProbePresentation.showsActionCard(
            presence: .enabled(folderName: "Probe", version: "0.10.0"),
            bundledVersion: "0.9.28"))
    }

    @Test func aProbeNeedingActionHidesTheCompactSettingsLink() {
        #expect(!PerformanceProbePresentation.showsCompactStatus(
            presence: .enabled(folderName: "Probe", version: "0.9.25"),
            bundledVersion: "0.9.28"))
        #expect(PerformanceProbePresentation.showsCompactStatus(
            presence: .enabled(folderName: "Probe", version: "0.9.28"),
            bundledVersion: "0.9.28"))
    }
}
