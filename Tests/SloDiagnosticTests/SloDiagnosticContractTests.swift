import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct SloDiagnosticContractTests {
    private func mod(_ uniqueId: String,
                     name: String? = nil,
                     folder: String,
                     version: String = "1.0.0",
                     enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: uniqueId, name: name ?? folder, folderName: folder,
                version: version, author: "A", description: "", nexusUrl: "",
                nexusModId: "", isEnabled: enabled, dependencies: [])
    }

    private func installation(version: String = "1.0.0", enabled: Bool = true)
        -> SloDiagnosticInstallation {
        let item = mod(SloDiagnosticContract.uniqueId, folder: "SLO",
                       version: version, enabled: enabled)
        guard case .found(let installation) = SloDiagnosticContract.discover(
            mods: [item], gameDir: URL(fileURLWithPath: "/Game"))
        else { Issue.record("SLO introuvable"); fatalError() }
        return installation
    }

    private func probe(_ presence: ModPresence,
                       bundled: String? = "1.0.0") -> SloDiagnosticProbeStatus {
        SloDiagnosticProbeStatus(presence: presence,
                                 action: ProbeBundle.action(bundled: bundled, presence: presence))
    }

    @Test func constantsAndInstallRoutesStayOnDocumentedContract() {
        #expect(SloDiagnosticContract.uniqueId == "neoiw.StardewLoadingOptimizer")
        #expect(SloDiagnosticContract.nexusId == 50153)
        #expect(SloDiagnosticContract.minimumVersion == [1, 0, 0])
        #expect(SloDiagnosticContract.detailedDiagnosticsKey == "EnableDetailedDiagnostics")
        #expect(SloDiagnosticContract.performanceMeasurementKey == "EnablePerformanceMeasurement")
        #expect(SloDiagnosticContract.installRoute(directDownloadUnavailable: false)
                == .directDownload(50153))
        #expect(SloDiagnosticContract.installRoute(directDownloadUnavailable: true)
                == .webPage(MissingDependencies.filesPage(nexusId: 50153)))
    }

    @Test func discoversTopLevelAndPausedInstallations() {
        #expect(SloDiagnosticContract.discover(mods: [], gameDir: URL(fileURLWithPath: "/Game"))
                == .absent)

        let active = installation()
        #expect(active.rootFolderName == "SLO")
        #expect(active.rootPhysicalFolderName == "SLO")
        #expect(active.activeRootPhysicalFolderName == "SLO")
        #expect(active.componentRelativePath == "")
        #expect(active.initialConfigURL.path == "/Game/Mods/SLO/config.json")
        #expect(active.activeConfigURL.path == "/Game/Mods/SLO/config.json")
        #expect(active.isEnabled)

        let paused = installation(enabled: false)
        #expect(paused.rootPhysicalFolderName == ".SLO")
        #expect(paused.activeRootPhysicalFolderName == "SLO")
        #expect(paused.initialConfigURL.path == "/Game/Mods/.SLO/config.json")
        #expect(paused.activeConfigURL.path == "/Game/Mods/SLO/config.json")
        #expect(!paused.isEnabled)
    }

    @Test func findsPausedNestedInstallationAndListsActivatedSiblings() {
        let slo = mod(SloDiagnosticContract.uniqueId, name: "Optimizer",
                      folder: "Pack/SLO", enabled: false)
        let sibling = mod("Example.Other", name: "Other mod",
                          folder: "Pack/Other", enabled: false)
        let pack = ModItem(uniqueId: "", name: "Pack", folderName: "Pack", version: "",
                           author: "A", description: "", nexusUrl: "", nexusModId: "",
                           isEnabled: false, dependencies: [], children: [slo, sibling],
                           isGroup: true)

        guard case .found(let found) = SloDiagnosticContract.discover(
            mods: [pack], gameDir: URL(fileURLWithPath: "/Game"))
        else { Issue.record("SLO imbriqué introuvable"); return }

        #expect(found.rootFolderName == "Pack")
        #expect(found.rootPhysicalFolderName == ".Pack")
        #expect(found.activeRootPhysicalFolderName == "Pack")
        #expect(found.componentRelativePath == "SLO")
        #expect(found.initialConfigURL.path == "/Game/Mods/.Pack/SLO/config.json")
        #expect(found.activeConfigURL.path == "/Game/Mods/Pack/SLO/config.json")
        #expect(found.activatedSiblingNames == ["Other mod"])
    }

    @Test func duplicateUniqueIdIsAmbiguous() {
        let first = mod(SloDiagnosticContract.uniqueId, folder: "First")
        let second = mod(SloDiagnosticContract.uniqueId.uppercased(), folder: "Second")
        #expect(SloDiagnosticContract.discover(mods: [first, second],
                                               gameDir: URL(fileURLWithPath: "/Game"))
                == .ambiguous(["First", "Second"]))
    }

    @Test func compatibilityHonorsVersionBoundaryAndStrictObjectConfig() {
        #expect(SloDiagnosticContract.compatibility(installation: installation(version: "0.9.9"),
                                                    configData: nil) == .outdated("0.9.9"))
        #expect(SloDiagnosticContract.compatibility(installation: installation(version: "1.0.0"),
                                                    configData: nil) == .missingConfig)
        #expect(SloDiagnosticContract.compatibility(installation: installation(),
                                                    configData: Data("[]".utf8)) == .invalidConfig)
        #expect(SloDiagnosticContract.compatibility(installation: installation(),
                                                    configData: Data("{\"Other\": 1}".utf8)) == .compatible)
        #expect(SloDiagnosticContract.compatibility(
            installation: installation(),
            configData: Data("{\"EnableDetailedDiagnostics\": 1}".utf8)) == .invalidConfig)
    }

    @Test func vanillaAndBusyStatesBlockPreparation() {
        let found = SloDiagnosticDiscovery.found(installation())
        let readyProbe = probe(.enabled(folderName: "Probe", version: "1.0.0"))
        #expect(SloDiagnosticContract.readiness(discovery: found, compatibility: .compatible,
                                               probe: readyProbe, nexusActivity: .idle,
                                               launchProfile: "Vanilla", busyReason: nil)
                == .blocked("vanilla"))
        #expect(SloDiagnosticContract.readiness(discovery: found, compatibility: .compatible,
                                               probe: readyProbe, nexusActivity: .idle,
                                               launchProfile: "SMAPI", busyReason: "benchmark")
                == .blocked("benchmark"))
    }

    @Test func probeBundleStatesAreExplicit() {
        let found = SloDiagnosticDiscovery.found(installation())
        func readiness(_ probe: SloDiagnosticProbeStatus) -> SloDiagnosticReadiness {
            SloDiagnosticContract.readiness(discovery: found, compatibility: .compatible,
                                            probe: probe, nexusActivity: .idle,
                                            launchProfile: "SMAPI", busyReason: nil)
        }

        #expect(readiness(probe(.absent)) == .probeInstallRequired(.install(version: "1.0.0")))
        #expect(readiness(probe(.enabled(folderName: "Probe", version: "0.9.0")))
                == .probeInstallRequired(.update(from: "0.9.0", to: "1.0.0")))
        #expect(readiness(probe(.absent, bundled: nil)) == .probeInstallRequired(.unavailable))
        #expect(readiness(probe(.paused(folderName: "Probe", version: "1.1.0"))) == .probePaused)
        #expect(readiness(probe(.enabled(folderName: "Probe", version: "1.1.0")))
                == .ready(installation()))
    }

    @Test func nexusActivityTracksSloDownloadAndPendingArchive() {
        let probe = probe(.enabled(folderName: "Probe", version: "1.0.0"))
        #expect(SloDiagnosticContract.readiness(discovery: .absent, compatibility: nil,
                                               probe: probe, nexusActivity: .downloading(modId: 50153),
                                               launchProfile: "SMAPI", busyReason: nil) == .sloDownloading)
        #expect(SloDiagnosticContract.readiness(discovery: .absent, compatibility: nil,
                                               probe: probe, nexusActivity: .awaitingInstall(modId: 50153),
                                               launchProfile: "SMAPI", busyReason: nil) == .sloDownloading)
        #expect(SloDiagnosticContract.readiness(discovery: .absent, compatibility: nil,
                                               probe: probe, nexusActivity: .downloading(modId: 42),
                                               launchProfile: "SMAPI", busyReason: nil)
                == .blocked("nexus-busy"))
    }
}
