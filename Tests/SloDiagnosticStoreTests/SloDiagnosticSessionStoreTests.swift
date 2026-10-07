import Foundation
import Testing
@testable import StarHubTHCore

@MainActor
@Suite struct SloDiagnosticSessionStoreTests {
    final class Box: @unchecked Sendable {
        var running = false
        var now = Date(timeIntervalSince1970: 1_000)
        var enabled: [String: Bool] = ["SLO": false, "Probe": false]
        var events: [String] = []
        var launchCount = 0
        var setChangesState = true
        var failRoot: String?
        var createSloCollisionOnFailure = false
    }

    private struct Fixture {
        let base: URL
        let support: URL
        let game: URL
        let log: URL
        let probe: URL
        let slo: SloDiagnosticInstallation
        let preparation: SloDiagnosticPreparation
    }

    private func fixture(original: String = #"{"Other":7}"#) throws -> Fixture {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let support = base.appendingPathComponent("Support", isDirectory: true)
        let game = base.appendingPathComponent("Game", isDirectory: true)
        let mods = game.appendingPathComponent("Mods", isDirectory: true)
        let sloRoot = mods.appendingPathComponent(".SLO", isDirectory: true)
        let probeRoot = mods.appendingPathComponent(".Probe", isDirectory: true)
        try FileManager.default.createDirectory(at: sloRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: probeRoot, withIntermediateDirectories: true)
        try Data(original.utf8).write(to: sloRoot.appendingPathComponent("config.json"))
        let log = base.appendingPathComponent("SMAPI-latest.txt")
        try Data("old\n".utf8).write(to: log)
        let probe = base.appendingPathComponent("ProbeData", isDirectory: true)
        try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
        let installation = SloDiagnosticInstallation(
            rootFolderName: "SLO", rootPhysicalFolderName: ".SLO",
            activeRootPhysicalFolderName: "SLO", componentRelativePath: "",
            version: "1.0.0", isEnabled: false,
            initialConfigURL: sloRoot.appendingPathComponent("config.json"),
            activeConfigURL: mods.appendingPathComponent("SLO/config.json"),
            activatedSiblingNames: [])
        return Fixture(base: base, support: support, game: game, log: log, probe: probe,
                       slo: installation,
                       preparation: SloDiagnosticPreparation(
                        slo: installation, probeRootFolderName: "Probe", probeWasEnabled: false))
    }

    private func runtime(_ fixture: Fixture, _ box: Box) -> SloDiagnosticRuntime {
        let mods = fixture.game.appendingPathComponent("Mods", isDirectory: true)
        return SloDiagnosticRuntime(
            isGameRunning: { box.running }, busyReason: { nil }, launchProfile: { "SMAPI" },
            modEnabled: { box.enabled[$0] },
            setModEnabled: { root, enabled in
                let planExists = SloDiagnosticSnapshotStore.hasPending(in: fixture.support)
                box.events.append("toggle:\(root):\(enabled):plan=\(planExists)")
                if root == box.failRoot {
                    if box.createSloCollisionOnFailure {
                        try? FileManager.default.createDirectory(
                            at: mods.appendingPathComponent(".SLO"),
                            withIntermediateDirectories: true)
                    }
                    return false
                }
                guard box.setChangesState else { return true }
                let source = mods.appendingPathComponent(enabled ? ".\(root)" : root)
                let destination = mods.appendingPathComponent(enabled ? root : ".\(root)")
                do {
                    try FileManager.default.moveItem(at: source, to: destination)
                    box.enabled[root] = enabled
                    return true
                } catch { return false }
            },
            grantOwnerWriteAccess: { _ in box.events.append("grant") },
            launchGame: {
                box.launchCount += 1; box.running = true; box.events.append("launch"); return true
            },
            rescan: { box.events.append("rescan") }, now: { box.now },
            sleep: { seconds in
                if seconds >= SloDiagnosticRuntime.pollSeconds {
                    try? await Task.sleep(for: .seconds(3_600))
                }
            })
    }

    @Test func happyPathPersistsBeforeMutationAndRestoresConfigBeforeRoots() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let box = Box()
        let store = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                               probeFiles: ProbeFiles(directory: f.probe))
        await store.start(f.preparation, runtime: runtime(f, box))
        #expect(box.launchCount == 1)
        #expect(box.events.first?.contains("plan=true") == true)
        let activeConfig = f.slo.activeConfigURL
        let diagnostic = try Data(contentsOf: activeConfig)
        let object = try #require(try JSONSerialization.jsonObject(with: diagnostic) as? [String: Any])
        #expect(object[SloDiagnosticContract.detailedDiagnosticsKey] as? Bool == true)
        #expect(object[SloDiagnosticContract.performanceMeasurementKey] as? Bool == true)

        try Data("old\n[OPTIMIZER CONFIG] detailedDiagnostics=True, performanceMeasurement=True.\n".utf8)
            .write(to: f.log)
        box.running = false
        await store.gameExited(runtime: runtime(f, box))

        guard case .report = store.state else {
            Issue.record("rapport attendu après restauration"); return
        }
        #expect(!SloDiagnosticSnapshotStore.hasPending(in: f.support))
        #expect(String(data: try Data(contentsOf: f.slo.initialConfigURL), encoding: .utf8)
                == #"{"Other":7}"#)
        #expect(box.enabled["SLO"] == false)
        #expect(box.enabled["Probe"] == false)
        let disableIndex = try #require(box.events.firstIndex { $0 == "toggle:SLO:false:plan=true" })
        #expect(disableIndex > (box.events.firstIndex(of: "launch") ?? 0))
        #expect(try SloDiagnosticReportStore.load(from: f.support) != nil)
    }

    @Test func changedDiagnosticFileRequiresResolutionAndExplicitOverwrite() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let box = Box()
        let store = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                               probeFiles: ProbeFiles(directory: f.probe))
        let rt = runtime(f, box)
        await store.start(f.preparation, runtime: rt)
        try Data(#"{"UserChanged":true}"#.utf8).write(to: f.slo.activeConfigURL)
        box.running = false
        await store.gameExited(runtime: rt)
        #expect(store.state == .recoveryBlocked(.configChanged))
        #expect(SloDiagnosticSnapshotStore.hasPending(in: f.support))
        await store.confirmOverwriteAndRestore(runtime: rt)
        #expect(!SloDiagnosticSnapshotStore.hasPending(in: f.support))
        #expect(box.enabled["SLO"] == false)
    }

    @Test func toggleCallbackWithoutStateChangeRollsBackAndNeverLaunches() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let box = Box(); box.setChangesState = false
        let store = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                               probeFiles: ProbeFiles(directory: f.probe))
        await store.start(f.preparation, runtime: runtime(f, box))
        #expect(box.launchCount == 0)
        #expect(store.state == .failed(.rootActivation("SLO")))
    }

    @Test func vanillaAndExclusiveOperationRefuseBeforeSnapshot() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let box = Box()
        let vanilla = SloDiagnosticRuntime(
            isGameRunning: { false }, busyReason: { nil }, launchProfile: { "Vanilla" },
            modEnabled: { box.enabled[$0] }, setModEnabled: { _, _ in true },
            grantOwnerWriteAccess: { _ in }, launchGame: { true }, rescan: {},
            now: { box.now }, sleep: { _ in })
        let store = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                               probeFiles: ProbeFiles(directory: f.probe))
        await store.start(f.preparation, runtime: vanilla)
        #expect(store.state == .failed(.vanillaProfile))
        #expect(!SloDiagnosticSnapshotStore.hasPending(in: f.support))
    }

    @Test func resumeRestoresClosedSessionAndSecondResumeDoesNothing() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let box = Box()
        let first = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                               probeFiles: ProbeFiles(directory: f.probe))
        let rt = runtime(f, box)
        await first.start(f.preparation, runtime: rt)
        var seen = try #require(try SloDiagnosticSnapshotStore.load(from: f.support))
        seen.gameSeen = true
        try SloDiagnosticSnapshotStore.save(seen, in: f.support)
        box.running = false
        let resumed = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                                 probeFiles: ProbeFiles(directory: f.probe))
        await resumed.resumeIfNeeded(mods: [], gameDir: f.game, runtime: rt)
        #expect(!SloDiagnosticSnapshotStore.hasPending(in: f.support))
        let toggles = box.events.filter { $0.hasPrefix("toggle:") }.count
        await resumed.resumeIfNeeded(mods: [], gameDir: f.game, runtime: rt)
        #expect(box.events.filter { $0.hasPrefix("toggle:") }.count == toggles)
    }

    @Test func restartWithinTimeoutWaitsButPastTimeoutRestores() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let box = Box()
        let original = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                                  probeFiles: ProbeFiles(directory: f.probe))
        let rt = runtime(f, box)
        await original.start(f.preparation, runtime: rt)
        box.running = false
        box.now = box.now.addingTimeInterval(30)
        let early = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                               probeFiles: ProbeFiles(directory: f.probe))
        await early.resumeIfNeeded(mods: [], gameDir: f.game, runtime: rt)
        #expect(early.state == .waitingForGame)
        #expect(SloDiagnosticSnapshotStore.hasPending(in: f.support))
        box.now = box.now.addingTimeInterval(61)
        let late = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                              probeFiles: ProbeFiles(directory: f.probe))
        await late.resumeIfNeeded(mods: [], gameDir: f.game, runtime: rt)
        #expect(!SloDiagnosticSnapshotStore.hasPending(in: f.support))
    }

    @Test func collisionAndMissingVolumeBlockRecovery() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let box = Box()
        let store = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                               probeFiles: ProbeFiles(directory: f.probe))
        let rt = runtime(f, box)
        await store.start(f.preparation, runtime: rt)
        box.running = false
        try FileManager.default.createDirectory(
            at: f.game.appendingPathComponent("Mods/.SLO"), withIntermediateDirectories: true)
        await store.gameExited(runtime: rt)
        #expect(store.state == .recoveryBlocked(.rootCollision("SLO")))
    }

    @Test func reportReceiptContainsNoRawConfiguration() throws {
        let f = try fixture(original: #"{"Secret":"do-not-store"}"#)
        defer { try? FileManager.default.removeItem(at: f.base) }
        let report = SloDiagnosticReport.build(
            log: .parse(""), probe: .init(session: nil, loads: [], inventory: nil),
            startedAt: Date())
        let receipt = SloDiagnosticReportReceipt(completedAt: Date(), sessionId: nil,
                                                  report: report,
                                                  sourceFingerprints: ["log": "abc"])
        try SloDiagnosticReportStore.save(receipt, in: f.support)
        #expect(try SloDiagnosticReportStore.load(from: f.support) == receipt)
        let bytes = try Data(contentsOf: SloDiagnosticReportStore.fileURL(in: f.support))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("do-not-store"))
    }

    @Test func durableExclusionUsesSnapshotExistenceEvenWhenUnreadable() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        try FileManager.default.createDirectory(at: f.support, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: SloDiagnosticSnapshotStore.fileURL(in: f.support))
        #expect(SloDiagnosticSnapshotStore.hasPending(in: f.support))
        #expect(SloDiagnosticExclusion.blocksOtherPerformanceWork(snapshotDirectory: f.support))
    }

    @Test func groupedSloSnapshotKeepsModsAsRecoveryRoot() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let component = "SLOComponent"
        let groupedConfig = f.game.appendingPathComponent("Mods/SLO/\(component)/config.json")
        let installation = SloDiagnosticInstallation(
            rootFolderName: "SLO", rootPhysicalFolderName: ".SLO",
            activeRootPhysicalFolderName: "SLO", componentRelativePath: component,
            version: "1.0.0", isEnabled: false,
            initialConfigURL: f.game.appendingPathComponent("Mods/.SLO/\(component)/config.json"),
            activeConfigURL: groupedConfig, activatedSiblingNames: [])
        try FileManager.default.createDirectory(
            at: installation.initialConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data(#"{"Other":7}"#.utf8).write(to: installation.initialConfigURL)
        let preparation = SloDiagnosticPreparation(
            slo: installation, probeRootFolderName: "Probe", probeWasEnabled: false)
        let box = Box()
        let store = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                               probeFiles: ProbeFiles(directory: f.probe))
        await store.start(preparation, runtime: runtime(f, box))
        let snapshot = try #require(try SloDiagnosticSnapshotStore.load(from: f.support))
        #expect(snapshot.modsRootURL == f.game.appendingPathComponent("Mods").resolvingSymlinksInPath())
        #expect(FileManager.default.fileExists(atPath: groupedConfig.path))
    }

    @Test func preparationRereadsConfigAtCurrentRootState() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let paused = f.game.appendingPathComponent("Mods/.SLO")
        let active = f.game.appendingPathComponent("Mods/SLO")
        try FileManager.default.moveItem(at: paused, to: active)
        let current = Data(#"{"ChangedWhileSheetWasOpen":true}"#.utf8)
        try current.write(to: f.slo.activeConfigURL)
        let box = Box(); box.enabled["SLO"] = true
        let store = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                               probeFiles: ProbeFiles(directory: f.probe))
        let rt = runtime(f, box)
        await store.start(f.preparation, runtime: rt)
        var snapshot = try #require(try SloDiagnosticSnapshotStore.load(from: f.support))
        #expect(snapshot.initialConfigURL == f.slo.activeConfigURL)
        #expect(snapshot.originalConfig == .bytes(current))
        snapshot.gameSeen = true
        try SloDiagnosticSnapshotStore.save(snapshot, in: f.support)
        box.running = false
        await store.gameExited(runtime: rt)
        #expect(try Data(contentsOf: f.slo.activeConfigURL) == current)
    }

    @Test func failedRollbackKeepsRecoveryActionVisible() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let box = Box(); box.failRoot = "Probe"; box.createSloCollisionOnFailure = true
        let store = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                               probeFiles: ProbeFiles(directory: f.probe))
        await store.start(f.preparation, runtime: runtime(f, box))
        #expect(store.state == .recoveryBlocked(.rootCollision("SLO")))
        #expect(SloDiagnosticSnapshotStore.hasPending(in: f.support))
    }

    @Test func automaticReloadKeepsTheCompletedReportVisible() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let report = SloDiagnosticReport.build(
            log: SloDiagnosticLog.parse(""),
            probe: .init(session: nil, loads: [], inventory: nil),
            startedAt: Date(timeIntervalSince1970: 10))
        try SloDiagnosticReportStore.save(.init(
            completedAt: Date(timeIntervalSince1970: 20), sessionId: nil,
            report: report, sourceFingerprints: [:]), in: f.support)
        let store = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                               probeFiles: ProbeFiles(directory: f.probe))

        await store.reload(mods: [], gameDir: f.game, runtime: runtime(f, Box()))

        #expect(store.state == .report(report))
    }
}
