import Foundation
import Testing
@testable import StarHubTHCore

@MainActor
@Suite struct SloDiagnosticPresentationTests {
    private let installation = SloDiagnosticInstallation(
        rootFolderName: "SLO", rootPhysicalFolderName: "SLO",
        activeRootPhysicalFolderName: "SLO", componentRelativePath: "",
        version: "1.0.0", isEnabled: true,
        initialConfigURL: URL(fileURLWithPath: "/Game/Mods/SLO/config.json"),
        activeConfigURL: URL(fileURLWithPath: "/Game/Mods/SLO/config.json"),
        activatedSiblingNames: [])

    @Test func missingSloUsesExpectedIdentityForBothInstallRoutes() {
        let direct = SloDiagnosticPresentation.make(
            state: .unavailable(.sloAbsent), directDownloadUnavailable: false)
        #expect(direct.action == .download(nexusId: 50153,
                                           uniqueId: "neoiw.StardewLoadingOptimizer"))
        let web = SloDiagnosticPresentation.make(
            state: .unavailable(.sloAbsent), directDownloadUnavailable: true)
        guard case .openPage(_, let id, let uniqueId) = web.action else {
            Issue.record("page Nexus attendue"); return
        }
        #expect(id == 50153)
        #expect(uniqueId == SloDiagnosticContract.uniqueId)
    }

    @Test func nexusProgressSuppressesDuplicateInstallAction() {
        let downloading = SloDiagnosticPresentation.make(
            state: .unavailable(.sloAbsent), directDownloadUnavailable: false,
            nexusActivity: .downloading(modId: 50153))
        let waiting = SloDiagnosticPresentation.make(
            state: .unavailable(.sloAbsent), directDownloadUnavailable: false,
            nexusActivity: .awaitingInstall(modId: 50153))
        #expect(downloading == .init(kind: .downloading, action: nil))
        #expect(waiting == .init(kind: .awaitingInstall, action: nil))
    }

    @Test func foundAfterScanOffersConfirmationAndNeverLaunchesDirectly() {
        let preparation = SloDiagnosticPreparation(
            slo: installation, probeRootFolderName: "Probe", probeWasEnabled: true)
        let presentation = SloDiagnosticPresentation.make(
            state: .ready(preparation), directDownloadUnavailable: false)
        #expect(presentation.kind == .ready)
        #expect(presentation.action == .confirm(preparation))
    }

    @Test func probeAndLifecycleStatesStayExplicit() {
        let action = ProbeBundle.Action.update(from: "0.8", to: "0.9")
        #expect(SloDiagnosticPresentation.make(
            state: .unavailable(.probeInstallRequired(action)),
            directDownloadUnavailable: false).action == .installProbe(action))
        #expect(SloDiagnosticPresentation.make(
            state: .unavailable(.probeInstallRequired(.unavailable)),
            directDownloadUnavailable: false).action == nil)
        #expect(SloDiagnosticPresentation.make(
            state: .running, directDownloadUnavailable: false).kind == .running)
        #expect(SloDiagnosticPresentation.make(
            state: .recoveryBlocked(.configChanged),
            directDownloadUnavailable: false).action == .restore)
    }
}
