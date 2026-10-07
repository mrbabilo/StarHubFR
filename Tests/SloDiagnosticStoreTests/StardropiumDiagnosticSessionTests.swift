import Foundation
import Testing
@testable import StarHubTHCore

@MainActor
struct StardropiumDiagnosticSessionTests {
    @MainActor final class Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var support: URL { base.appendingPathComponent("Support") }
        var game: URL { base.appendingPathComponent("Game") }
        var mods: URL { game.appendingPathComponent("Mods") }
        var log: URL { base.appendingPathComponent("log.txt") }
        var reportedModsRoot: URL?
        var running = false
        var launchSucceeds = true
        var enabled = ["Stardropium": false, "Probe": false]
        var launches = 0
        let original: Data?
        let now = Date()

        init(original: Data? = Data(#"{"EnableMemoryOptimization":false,"Other":7}"#.utf8)) throws {
            self.original = original
            for name in enabled.keys {
                try FileManager.default.createDirectory(at: mods.appendingPathComponent("." + name), withIntermediateDirectories: true)
            }
            if let original { try original.write(to: mods.appendingPathComponent(".Stardropium/config.json")) }
            try "old journal".write(to: log, atomically: true, encoding: .utf8)
        }
        var preparation: SloDiagnosticPreparation {
            .init(slo: .init(rootFolderName: "Stardropium", rootPhysicalFolderName: ".Stardropium",
                activeRootPhysicalFolderName: "Stardropium", componentRelativePath: "", version: "0.2.2-beta",
                isEnabled: false, initialConfigURL: mods.appendingPathComponent(".Stardropium/config.json"),
                activeConfigURL: mods.appendingPathComponent("Stardropium/config.json"), activatedSiblingNames: []),
                probeRootFolderName: "Probe", probeWasEnabled: false)
        }
        func store() -> SloDiagnosticSessionStore {
            .init(applicationSupport: support, logURL: log,
                  probeFiles: ProbeFiles(directory: base.appendingPathComponent("ProbeData")), kind: .stardropium)
        }
        var runtime: SloDiagnosticRuntime {
            .init(modsRootURL: reportedModsRoot ?? mods, isGameRunning: { self.running }, busyReason: { nil }, launchProfile: { "SMAPI" },
                  modEnabled: { self.enabled[$0] }, setModEnabled: { name, active in
                #expect(SloDiagnosticExclusion.blocksOtherPerformanceWork(snapshotDirectory: self.support))
                do {
                    try FileManager.default.moveItem(at: self.mods.appendingPathComponent(active ? "." + name : name),
                        to: self.mods.appendingPathComponent(active ? name : "." + name))
                    self.enabled[name] = active
                    return true
                } catch { return false }
            }, grantOwnerWriteAccess: { _ in }, launchGame: {
                self.launches += 1; self.running = self.launchSucceeds; return self.launchSucceeds
            }, rescan: {}, now: { self.now }, sleep: { seconds in
                if seconds >= SloDiagnosticRuntime.pollSeconds { try? await Task.sleep(for: .seconds(3600)) }
            })
        }
        func clean() { try? FileManager.default.removeItem(at: base) }
    }

    @Test func activatesConfiguresRestoresAndRetainsOnlyFreshReport() async throws {
        let f = try Fixture(); defer { f.clean() }
        let store = f.store(); defer { store.monitorTask?.cancel() }
        await store.start(f.preparation, runtime: f.runtime)
        #expect(f.launches == 1)
        #expect(f.enabled.values.allSatisfy { $0 })
        let config = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: f.preparation.slo.activeConfigURL)) as? [String: Any])
        #expect(config["EnableMemoryOptimization"] as? Bool == true)
        #expect(config["AutoTrimWorkingSetOnNewDay"] as? Bool == true)
        #expect(config["Other"] as? Int == 7)
        let start = ISO8601DateFormatter().string(from: f.now).replacingOccurrences(of: "Z", with: " UTC")
        let log = "old journal\n[14:36:40 TRACE SMAPI] Log started at \(start)\n[14:54:12 INFO Stardropium] [Morning Memory Optimizer (Background)] RAM: 1561 MB -> 1565 MB (Managed Heap: 3749 MB -> 3751 MB, 0 cached textures purged/bounded)."
        try log.write(to: f.log, atomically: true, encoding: .utf8)
        f.running = false
        await store.gameExited(runtime: f.runtime)
        #expect(f.enabled.values.allSatisfy { !$0 })
        #expect(try Data(contentsOf: f.preparation.slo.initialConfigURL) == f.original)
        #expect(!SloDiagnosticExclusion.blocksOtherPerformanceWork(snapshotDirectory: f.support))
        #expect(store.memoryReceipt?.report.samples.first?.residentDelta == 4)
        #expect(f.store().memoryReceipt?.report.samples.count == 1)
        #expect(store.lastReceipt == nil)
    }

    @Test func absentConfigIsRemovedAndOldJournalIsNotReused() async throws {
        let f = try Fixture(original: nil); defer { f.clean() }
        let store = f.store(); defer { store.monitorTask?.cancel() }
        await store.start(f.preparation, runtime: f.runtime)
        f.running = false
        await store.gameExited(runtime: f.runtime)
        #expect(!FileManager.default.fileExists(atPath: f.preparation.slo.initialConfigURL.path))
        #expect(store.memoryReceipt?.report.samples.isEmpty == true)
    }

    @Test func failedLaunchRollsBackAndConcurrentSloIsBlocked() async throws {
        let f = try Fixture(); defer { f.clean() }
        let store = f.store(); defer { store.monitorTask?.cancel() }
        await store.start(f.preparation, runtime: f.runtime)
        f.running = false
        let other = SloDiagnosticSessionStore(applicationSupport: f.support, logURL: f.log,
                                              probeFiles: ProbeFiles(directory: f.base.appendingPathComponent("ProbeData")))
        await other.start(f.preparation, runtime: f.runtime)
        #expect(other.state == .failed(.busy("diagnostic-pending")))
        #expect(f.launches == 1)
        await store.gameExited(runtime: f.runtime)
        f.launchSucceeds = false
        await store.start(f.preparation, runtime: f.runtime)
        #expect(store.state == .failed(.launch))
        #expect(f.enabled.values.allSatisfy { !$0 })
        #expect(try Data(contentsOf: f.preparation.slo.initialConfigURL) == f.original)
        #expect(!SloDiagnosticExclusion.blocksOtherPerformanceWork(snapshotDirectory: f.support))
    }

    @Test func configEditedDuringGameRequiresExplicitRecovery() async throws {
        let f = try Fixture(); defer { f.clean() }
        let store = f.store(); defer { store.monitorTask?.cancel() }
        await store.start(f.preparation, runtime: f.runtime)
        let edit = Data(#"{"Other":99}"#.utf8)
        try edit.write(to: f.preparation.slo.activeConfigURL)
        await store.confirmOverwriteAndRestore(runtime: f.runtime)
        #expect(store.state == .failed(.gameRunning))
        #expect(try Data(contentsOf: f.preparation.slo.activeConfigURL) == edit)
        f.running = false
        await store.gameExited(runtime: f.runtime)
        #expect(store.state == .recoveryBlocked(.configChanged))
        #expect(try Data(contentsOf: f.preparation.slo.activeConfigURL) == edit)
        #expect(SloDiagnosticExclusion.blocksOtherPerformanceWork(snapshotDirectory: f.support))
        await store.confirmOverwriteAndRestore(runtime: f.runtime)
        #expect(try Data(contentsOf: f.preparation.slo.initialConfigURL) == f.original)
        #expect(!SloDiagnosticExclusion.blocksOtherPerformanceWork(snapshotDirectory: f.support))
    }

    @Test func restartRecoversSnapshotBeforeLaunchingAnythingElse() async throws {
        let f = try Fixture(); defer { f.clean() }
        let first = f.store()
        await first.start(f.preparation, runtime: f.runtime)
        first.monitorTask?.cancel()
        let directory = PerformanceDiagnosticKind.stardropium.directory(in: f.support)
        var snapshot = try #require(try SloDiagnosticSnapshotStore.load(from: directory))
        snapshot.gameSeen = true
        try SloDiagnosticSnapshotStore.save(snapshot, in: directory)
        f.running = false
        let restarted = f.store(); defer { restarted.monitorTask?.cancel() }
        await restarted.resumeIfNeeded(mods: [], gameDir: f.game, runtime: f.runtime)
        #expect(f.enabled.values.allSatisfy { !$0 })
        #expect(try Data(contentsOf: f.preparation.slo.initialConfigURL) == f.original)
        #expect(!SloDiagnosticExclusion.blocksOtherPerformanceWork(snapshotDirectory: f.support))
        #expect(f.launches == 1)
    }
    @Test func unreadableExistingConfigIsNotTreatedAsMissing() async throws {
        let f = try Fixture(original: nil); defer { f.clean() }
        try FileManager.default.createDirectory(at: f.preparation.slo.initialConfigURL, withIntermediateDirectories: true)
        let store = f.store(); defer { store.monitorTask?.cancel() }
        await store.start(f.preparation, runtime: f.runtime)
        #expect(store.state == .failed(.invalidConfig))
        #expect(f.launches == 0)
        #expect(f.enabled.values.allSatisfy { !$0 })
        #expect(!SloDiagnosticExclusion.blocksOtherPerformanceWork(snapshotDirectory: f.support))
    }

    @Test func rechecksConfigLocationWhenModWasPausedAfterPreview() async throws {
        let f = try Fixture(); defer { f.clean() }
        let old = f.preparation.slo
        let stale = SloDiagnosticPreparation(slo: .init(rootFolderName: old.rootFolderName,
            rootPhysicalFolderName: old.activeRootPhysicalFolderName,
            activeRootPhysicalFolderName: old.activeRootPhysicalFolderName, componentRelativePath: "",
            version: old.version, isEnabled: true, initialConfigURL: old.activeConfigURL,
            activeConfigURL: old.activeConfigURL, activatedSiblingNames: []),
            probeRootFolderName: "Probe", probeWasEnabled: false)
        let store = f.store(); defer { store.monitorTask?.cancel() }
        await store.start(stale, runtime: f.runtime)
        f.running = false
        await store.gameExited(runtime: f.runtime)
        #expect(try Data(contentsOf: old.initialConfigURL) == f.original)
        #expect(f.enabled.values.allSatisfy { !$0 })
    }

    @Test func reportWriteFailureStillRestoresEverything() async throws {
        let f = try Fixture(); defer { f.clean() }
        let store = f.store(); defer { store.monitorTask?.cancel() }
        await store.start(f.preparation, runtime: f.runtime)
        let directory = try #require(PerformanceDiagnosticKind.stardropium.directory(in: f.support))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("memory_report.json"), withIntermediateDirectories: true)
        f.running = false
        await store.gameExited(runtime: f.runtime)
        #expect(store.state == .failed(.snapshotWrite))
        #expect(try Data(contentsOf: f.preparation.slo.initialConfigURL) == f.original)
        #expect(f.enabled.values.allSatisfy { !$0 })
        #expect(!SloDiagnosticExclusion.blocksOtherPerformanceWork(snapshotDirectory: f.support))
    }

    @Test func restoreRechecksThatGameIsStillClosed() async throws {
        let f = try Fixture(); defer { f.clean() }
        let store = f.store(); defer { store.monitorTask?.cancel() }
        await store.start(f.preparation, runtime: f.runtime)
        var snapshot = try #require(try SloDiagnosticSnapshotStore.load(from: PerformanceDiagnosticKind.stardropium.directory(in: f.support)))
        let prepared = try Data(contentsOf: f.preparation.slo.activeConfigURL)
        #expect(await store.restore(snapshot: &snapshot, runtime: f.runtime) == false)
        #expect(try Data(contentsOf: f.preparation.slo.activeConfigURL) == prepared)
        #expect(f.enabled.values.allSatisfy { $0 })
        f.running = false
        await store.gameExited(runtime: f.runtime)
    }

    @Test func changedGameDirectoryBlocksRestorationBeforeAnyMutation() async throws {
        let f = try Fixture(); defer { f.clean() }
        let store = f.store(); defer { store.monitorTask?.cancel() }
        await store.start(f.preparation, runtime: f.runtime)
        let prepared = try Data(contentsOf: f.preparation.slo.activeConfigURL)
        let other = f.base.appendingPathComponent("AnotherGame/Mods")
        try FileManager.default.createDirectory(at: other.appendingPathComponent(".Stardropium"), withIntermediateDirectories: true)
        f.reportedModsRoot = other
        f.running = false
        await store.gameExited(runtime: f.runtime)
        #expect(store.state == .recoveryBlocked(.gameDirectoryChanged))
        #expect(try Data(contentsOf: f.preparation.slo.activeConfigURL) == prepared)
        #expect(f.enabled.values.allSatisfy { $0 })
        #expect(SloDiagnosticExclusion.blocksOtherPerformanceWork(snapshotDirectory: f.support))
        #expect(DiagnosticModToggle.enabled(root: "Stardropium", modsRoot: other) == false)
        f.reportedModsRoot = f.mods
        await store.resumeIfNeeded(mods: [], gameDir: f.game, runtime: f.runtime)
        // Returning to the original game folder allows restoration.
        f.running = false
        await store.gameExited(runtime: f.runtime)
        #expect(try Data(contentsOf: f.preparation.slo.initialConfigURL) == f.original)
        #expect(f.enabled.values.allSatisfy { !$0 })
    }

}
