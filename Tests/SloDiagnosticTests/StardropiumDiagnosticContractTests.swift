import Foundation
import Testing
@testable import StarHubTHCore

struct StardropiumDiagnosticContractTests {
    @Test func preparesOnlyMorningMemoryOptions() throws {
        let original = Data(#"{"EnableMemoryOptimization":false,"AutoTrimWorkingSetOnNewDay":false,"EnableLiveDiagnostics":false,"LowMemoryMode":true,"Other":17}"#.utf8)
        let prepared = try SloDiagnosticTransaction.prepare(original: original, version: "0.2.2-beta", kind: .stardropium)
        let values = try #require(try JSONSerialization.jsonObject(with: prepared.data) as? [String: Any])
        #expect(values["EnableMemoryOptimization"] as? Bool == true)
        #expect(values["AutoTrimWorkingSetOnNewDay"] as? Bool == true)
        #expect(values["EnableLiveDiagnostics"] as? Bool == false)
        #expect(values["LowMemoryMode"] as? Bool == true)
        #expect(values["Other"] as? Int == 17)
        #expect(values["EnableDetailedDiagnostics"] == nil)
        #expect(prepared.original == .bytes(original))
    }

    @Test func missingConfigAndInvalidInputs() throws {
        let prepared = try SloDiagnosticTransaction.prepare(original: nil, version: "0.2.2-beta", kind: .stardropium)
        #expect(prepared.original == .missing)
        let values = try #require(try JSONSerialization.jsonObject(with: prepared.data) as? [String: Any])
        #expect(values.count == 2)
        #expect(throws: (any Error).self) {
            try SloDiagnosticTransaction.prepare(original: Data(), version: "0.2.2-beta", kind: .stardropium)
        }
        #expect(throws: (any Error).self) {
            try SloDiagnosticTransaction.prepare(original: Data(#"{"EnableMemoryOptimization":1}"#.utf8), version: "0.2.2-beta", kind: .stardropium)
        }
        #expect(throws: (any Error).self) {
            try SloDiagnosticTransaction.prepare(original: Data("[]".utf8), version: "0.2.2-beta", kind: .stardropium)
        }
        #expect(throws: (any Error).self) {
            try SloDiagnosticTransaction.prepare(original: nil, version: "0.1.0", kind: .stardropium)
        }
    }

    @Test func installRouteAndNamespaceStaySeparate() {
        #expect(PerformanceDiagnosticKind.stardropium.uniqueId == "Arshia1381.Stardropium")
        #expect(PerformanceDiagnosticKind.stardropium.nexusId == 52803)
        let root = URL(fileURLWithPath: "/tmp/diagnostics")
        #expect(PerformanceDiagnosticKind.slo.directory(in: root) == root)
        #expect(PerformanceDiagnosticKind.stardropium.directory(in: root) != root)
        #expect(SloDiagnosticContract.installRoute(directDownloadUnavailable: false, kind: .stardropium) == .directDownload(52803))
    }
}

extension StardropiumDiagnosticContractTests {
    private func mod(_ id: String, folder: String, enabled: Bool = false, children: [ModItem]? = nil) -> ModItem {
        ModItem(uniqueId: id, name: folder, folderName: folder, version: "0.2.2-beta", author: "", description: "",
                nexusUrl: "", nexusModId: "", isEnabled: enabled, dependencies: [], children: children, isGroup: children != nil)
    }

    @Test func discoversPausedPackAndRejectsDuplicateInstallations() throws {
        let child = mod("Arshia1381.Stardropium", folder: "Pack/Stardropium")
        let root = mod("", folder: "Pack", children: [child, mod("Author.Other", folder: "Pack/Other")])
        let game = URL(fileURLWithPath: "/tmp/Game")
        let discovery = SloDiagnosticContract.discover(mods: [root], gameDir: game, kind: .stardropium)
        guard case .found(let installation) = discovery else { Issue.record("installation attendue"); return }
        #expect(installation.initialConfigURL.path.hasSuffix("Mods/.Pack/Stardropium/config.json"))
        #expect(installation.activeConfigURL.path.hasSuffix("Mods/Pack/Stardropium/config.json"))
        #expect(installation.activatedSiblingNames == ["Pack/Other"])
        #expect(SloDiagnosticContract.discover(mods: [root], gameDir: game) == .absent)
        guard case .ambiguous = SloDiagnosticContract.discover(mods: [root, mod("Arshia1381.Stardropium", folder: "OtherCopy")], gameDir: game, kind: .stardropium) else { Issue.record("doublon ignoré"); return }
    }

    @Test func presentationUsesStardropiumInstallRouteAndDownloadState() {
        let absent = SloDiagnosticPresentation.make(state: .unavailable(.sloAbsent), directDownloadUnavailable: false, kind: .stardropium)
        #expect(absent.action == .download(nexusId: 52803, uniqueId: "Arshia1381.Stardropium"))
        let web = SloDiagnosticPresentation.make(state: .unavailable(.sloAbsent), directDownloadUnavailable: true, kind: .stardropium)
        guard case .openPage(_, let id, let uniqueId) = web.action else { Issue.record("page Nexus attendue"); return }
        #expect(id == 52803)
        #expect(uniqueId == "Arshia1381.Stardropium")
        let waiting = SloDiagnosticPresentation.make(state: .idle, directDownloadUnavailable: false,
            nexusActivity: .awaitingInstall(modId: 52803), kind: .stardropium)
        #expect(waiting.kind == .awaitingInstall)
        #expect(waiting.action == nil)
    }
    @Test func rejectsLogsFromAnotherLaunchEvenWithFreshFileDate() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-10-07T12:36:40Z"))
        let log = """
        [14:36:40 TRACE SMAPI] Log started at 2026-10-07T12:36:40 UTC
        [14:54:12 INFO Stardropium] [Morning Memory Optimizer (Background)] RAM: 1 MB -> 2 MB (Managed Heap: 3 MB -> 4 MB, 0 cached textures purged/bounded).
        """
        #expect(StardropiumDiagnosticReceipt.correlatedReport(log: log, launchRequestedAt: start).samples.count == 1)
        #expect(StardropiumDiagnosticReceipt.correlatedReport(log: log, launchRequestedAt: start.addingTimeInterval(3600)).samples.isEmpty)
        #expect(StardropiumDiagnosticReceipt.correlatedReport(log: log, launchRequestedAt: start.addingTimeInterval(-3600)).samples.isEmpty)
        #expect(StardropiumDiagnosticReceipt.correlatedReport(log: log, launchRequestedAt: nil).samples.isEmpty)
    }

}
