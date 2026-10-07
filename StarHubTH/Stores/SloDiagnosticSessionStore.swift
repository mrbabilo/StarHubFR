import CoreFoundation
import Foundation
import Observation
@MainActor
@Observable
public final class SloDiagnosticSessionStore {
    public enum State: Equatable {
        case idle
        case unavailable(SloDiagnosticReadiness)
        case ready(SloDiagnosticPreparation)
        case preparing
        case waitingForGame
        case running
        case restoring
        case report(SloDiagnosticReport)
        case recoveryBlocked(SloDiagnosticRecoveryConflict)
        case failed(SloDiagnosticFailure)
    }
    public private(set) var state: State = .idle
    public private(set) var lastReceipt: SloDiagnosticReportReceipt?
    @ObservationIgnored private let applicationSupport: URL?
    @ObservationIgnored private let logURL: URL
    @ObservationIgnored private let probeFiles: ProbeFiles
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var finalizing = false
    @ObservationIgnored private var pendingReport: SloDiagnosticReport?
    public init(applicationSupport: URL?, logURL: URL, probeFiles: ProbeFiles) {
        self.applicationSupport = applicationSupport
        self.logURL = logURL
        self.probeFiles = probeFiles
        self.lastReceipt = try? SloDiagnosticReportStore.load(from: applicationSupport)
        if let report = lastReceipt?.report { state = .report(report) }
    }
    public func reload(mods: [ModItem], gameDir: URL, runtime: SloDiagnosticRuntime,
                       preserveReport: Bool = true) async {
        generation += 1
        let currentGeneration = generation
        if SloDiagnosticSnapshotStore.hasPending(in: applicationSupport) { return }
        if preserveReport, let report = lastReceipt?.report {
            state = .report(report)
            return
        }
        let discovery = SloDiagnosticContract.discover(mods: mods, gameDir: gameDir)
        var compatibility: SloDiagnosticCompatibility?
        if case .found(let installation) = discovery {
            let data = FileManager.default.contents(atPath: installation.initialConfigURL.path)
            compatibility = SloDiagnosticContract.compatibility(installation: installation,
                                                                  configData: data)
        }
        let presence = ModPresence.resolve(uniqueId: ModPresence.probeId, in: mods)
        let bundledProbeVersion = ProbeBundle.bundledFolder(resourcesURL: Bundle.main.resourceURL)
            .flatMap(ProbeBundle.version(ofFolder:))
        let action = ProbeBundle.action(bundled: bundledProbeVersion, presence: presence)
        let readiness = SloDiagnosticContract.readiness(
            discovery: discovery, compatibility: compatibility,
            probe: SloDiagnosticProbeStatus(presence: presence, action: action), nexusActivity: .idle,
            launchProfile: runtime.launchProfile(), busyReason: runtime.busyReason())
        guard currentGeneration == generation else { return }
        if case .found(let slo) = discovery, let probeFolder = presence.folderName,
           case .upToDate = action {
            let root = topRoot(of: probeFolder, in: mods)
            let enabled: Bool
            if case .enabled = presence { enabled = true } else { enabled = false }
            switch readiness {
            case .ready, .sloPaused, .probePaused:
                state = .ready(SloDiagnosticPreparation(slo: slo,
                                                        probeRootFolderName: root,
                                                        probeWasEnabled: enabled))
                return
            default: break
            }
        }
        state = .unavailable(readiness)
    }
    public func start(_ preparation: SloDiagnosticPreparation,
                      runtime: SloDiagnosticRuntime) async {
        guard runtime.launchProfile() != "Vanilla" else { state = .failed(.vanillaProfile); return }
        guard !runtime.isGameRunning() else { state = .failed(.gameRunning); return }
        if let reason = runtime.busyReason() { state = .failed(.busy(reason)); return }
        guard !SloDiagnosticSnapshotStore.hasPending(in: applicationSupport) else {
            state = .failed(.busy("diagnostic-pending")); return
        }
        state = .preparing
        let installation = preparation.slo
        let rootNames = orderedUnique([installation.rootFolderName,
                                       preparation.probeRootFolderName])
        var roots: [SloDiagnosticRootSnapshot] = []
        for name in rootNames {
            guard let enabled = runtime.modEnabled(name) else {
                state = .failed(.rootActivation(name)); return
            }
            roots.append(SloDiagnosticRootSnapshot(
                logicalName: name, initialPhysicalName: enabled ? name : ".\(name)",
                activePhysicalName: name, initiallyEnabled: enabled))
        }
        guard let sloWasEnabled = roots.first(where: { $0.logicalName.caseInsensitiveCompare(
            installation.rootFolderName) == .orderedSame })?.initiallyEnabled
        else { state = .failed(.invalidConfig); return }
        let initialConfigURL = sloWasEnabled ? installation.activeConfigURL : installation.initialConfigURL
        let original = FileManager.default.contents(atPath: initialConfigURL.path)
        guard let prepared = try? SloDiagnosticTransaction.prepare(
            original: original, version: installation.version) else {
            state = .failed(.invalidConfig); return
        }
        let known = Set(probeFiles.sessions().sessions.map(\.id))
        var snapshot = SloDiagnosticSnapshot(
            startedAt: runtime.now(), modsRootURL: modsRootURL(for: installation),
            roots: roots, initialConfigURL: initialConfigURL,
            activeConfigURL: installation.activeConfigURL, originalConfig: prepared.original,
            diagnosticConfig: prepared.data, acceptedDiagnosticSHA256: [prepared.sha256],
            logBookmark: SloDiagnosticSourceReader.bookmark(logURL: logURL),
            knownProbeSessionIDs: known)
        do { try SloDiagnosticSnapshotStore.save(snapshot, in: applicationSupport) }
        catch { state = .failed(.snapshotWrite); return }
        for root in roots where !root.initiallyEnabled {
            guard await runtime.setModEnabled(root.logicalName, true),
                  runtime.modEnabled(root.logicalName) == true else {
                guard await rollback(snapshot: snapshot, runtime: runtime) else { return }
                state = .failed(.rootActivation(root.logicalName)); return
            }
            snapshot.activatedRootFolderNames.insert(root.logicalName)
            try? SloDiagnosticSnapshotStore.save(snapshot, in: applicationSupport)
        }
        do {
            try runtime.grantOwnerWriteAccess(installation.activeConfigURL.deletingLastPathComponent())
            try prepared.data.write(to: installation.activeConfigURL, options: .atomic)
            guard FileManager.default.contents(atPath: installation.activeConfigURL.path)
                    .map(SloDiagnosticTransaction.sha256) == prepared.sha256 else { throw CocoaError(.fileWriteUnknown) }
            snapshot.configWritten = true
            try SloDiagnosticSnapshotStore.save(snapshot, in: applicationSupport)
        } catch {
            guard await rollback(snapshot: snapshot, runtime: runtime) else { return }
            state = .failed(.configWrite); return
        }
        snapshot.launchRequestedAt = runtime.now()
        do { try SloDiagnosticSnapshotStore.save(snapshot, in: applicationSupport) }
        catch { guard await rollback(snapshot: snapshot, runtime: runtime) else { return }
            state = .failed(.snapshotWrite); return }
        guard runtime.launchGame() else {
            guard await rollback(snapshot: snapshot, runtime: runtime) else { return }
            state = .failed(.launch); return
        }
        state = .waitingForGame
        startMonitoring(runtime: runtime)
    }
    public func gameExited(runtime: SloDiagnosticRuntime) async {
        guard SloDiagnosticSnapshotStore.hasPending(in: applicationSupport) else { return }
        monitorTask?.cancel()
        await runtime.sleep(SloDiagnosticRuntime.sourceSettleSeconds)
        await finalize(runtime: runtime)
    }
    public func resumeIfNeeded(mods: [ModItem], gameDir: URL,
                               runtime: SloDiagnosticRuntime) async {
        guard SloDiagnosticSnapshotStore.hasPending(in: applicationSupport) else { return }
        let snapshot: SloDiagnosticSnapshot
        do { snapshot = try requireSnapshot() }
        catch { state = .failed(.snapshotUnreadable); return }
        guard validateRootAvailability(snapshot) == nil else {
            state = .recoveryBlocked(validateRootAvailability(snapshot)!); return
        }
        if runtime.isGameRunning() {
            var updated = snapshot
            if !updated.gameSeen {
                updated.gameSeen = true
                try? SloDiagnosticSnapshotStore.save(updated, in: applicationSupport)
            }
            state = .running
            startMonitoring(runtime: runtime)
            return
        }
        guard let requested = snapshot.launchRequestedAt else {
            _ = await rollback(snapshot: snapshot, runtime: runtime); return
        }
        if snapshot.gameSeen || runtime.now().timeIntervalSince(requested) >= SloDiagnosticRuntime.launchTimeout {
            await runtime.sleep(SloDiagnosticRuntime.sourceSettleSeconds)
            await finalize(runtime: runtime)
        } else {
            state = .waitingForGame
            startMonitoring(runtime: runtime)
        }
    }
    public func confirmOverwriteAndRestore(runtime: SloDiagnosticRuntime) async {
        guard var snapshot = try? requireSnapshot() else { return }
        if let conflict = validateRootAvailability(snapshot) {
            state = .recoveryBlocked(conflict)
            return
        }
        state = .restoring
        do {
            let url = currentConfigURL(snapshot)
            try runtime.grantOwnerWriteAccess(url.deletingLastPathComponent())
            switch snapshot.originalConfig {
            case .missing:
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            case .bytes(let data): try data.write(to: url, options: .atomic)
            }
            snapshot.configRestored = true
            try SloDiagnosticSnapshotStore.save(snapshot, in: applicationSupport)
            guard await restoreRoots(&snapshot, runtime: runtime) else { return }
            try SloDiagnosticSnapshotStore.clear(in: applicationSupport)
            await runtime.rescan()
            if let report = pendingReport ?? lastReceipt?.report { state = .report(report) }
            else { state = .idle }
        } catch { state = .recoveryBlocked(.configChanged) }
    }
    private func startMonitoring(runtime: SloDiagnosticRuntime) {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while let self, !Task.isCancelled,
                  let snapshot = try? self.requireSnapshot() {
                if runtime.isGameRunning() {
                    if !snapshot.gameSeen {
                        var updated = snapshot; updated.gameSeen = true
                        try? SloDiagnosticSnapshotStore.save(updated, in: self.applicationSupport)
                    }
                    self.state = .running
                } else if snapshot.gameSeen {
                    await runtime.sleep(SloDiagnosticRuntime.sourceSettleSeconds)
                    await self.finalize(runtime: runtime); return
                } else if let requested = snapshot.launchRequestedAt,
                          runtime.now().timeIntervalSince(requested) >= SloDiagnosticRuntime.launchTimeout {
                    await self.finalize(runtime: runtime); return
                }
                await runtime.sleep(SloDiagnosticRuntime.pollSeconds)
            }
        }
    }
    private func finalize(runtime: SloDiagnosticRuntime) async {
        guard !finalizing, var snapshot = try? requireSnapshot() else { return }
        finalizing = true
        defer { finalizing = false }
        state = .restoring
        let logData = FileManager.default.contents(atPath: logURL.path)
        let modified = (try? FileManager.default.attributesOfItem(atPath: logURL.path))?[.modificationDate] as? Date
        let logText = snapshot.launchRequestedAt.flatMap {
            SloDiagnosticSourceReader.newLog(current: logData, bookmark: snapshot.logBookmark,
                                             modified: modified, launchRequestedAt: $0)
        } ?? ""
        let parsedLog = SloDiagnosticLog.parse(logText)
        let sources = SloDiagnosticCorrelation.select(
            snapshot: snapshot, sessions: probeFiles.sessions(), inventory: probeFiles.inventory(),
            loads: probeFiles.loads())
        var candidate = sources.candidate
        if case .normalizationCandidate(let sha) = candidate?.configMatch {
            let current = FileManager.default.contents(atPath: currentConfigURL(snapshot).path)
            if validatesNormalization(data: current, sha: sha, log: parsedLog) {
                snapshot.acceptedDiagnosticSHA256.insert(sha)
                try? SloDiagnosticSnapshotStore.save(snapshot, in: applicationSupport)
            } else { candidate = nil }
        }
        let report = SloDiagnosticReport.build(
            log: parsedLog, probe: candidate?.input ?? .init(session: nil, loads: [], inventory: nil),
            startedAt: snapshot.startedAt)
        pendingReport = report
        var fingerprints: [String: String] = [:]
        if let logData { fingerprints["log"] = SloDiagnosticTransaction.sha256(logData) }
        if let current = FileManager.default.contents(atPath: currentConfigURL(snapshot).path) {
            fingerprints["config"] = SloDiagnosticTransaction.sha256(current)
        }
        let receipt = SloDiagnosticReportReceipt(
            completedAt: runtime.now(), sessionId: candidate?.selectedSessionId,
            report: report, sourceFingerprints: fingerprints)
        try? SloDiagnosticReportStore.save(receipt, in: applicationSupport)
        lastReceipt = receipt
        guard await restore(snapshot: &snapshot, runtime: runtime) else { return }
        try? SloDiagnosticSnapshotStore.clear(in: applicationSupport)
        await runtime.rescan()
        state = .report(report)
    }
    private func rollback(snapshot: SloDiagnosticSnapshot, runtime: SloDiagnosticRuntime) async -> Bool {
        var copy = snapshot
        guard await restore(snapshot: &copy, runtime: runtime) else { return false }
        if copy.configRestored && copy.restoredRootFolderNames.count == copy.roots.count {
            try? SloDiagnosticSnapshotStore.clear(in: applicationSupport)
        }
        return true
    }
    private func restore(snapshot: inout SloDiagnosticSnapshot,
                         runtime: SloDiagnosticRuntime) async -> Bool {
        if let conflict = validateRootAvailability(snapshot) {
            state = .recoveryBlocked(conflict); return false
        }
        let url = currentConfigURL(snapshot)
        let current = FileManager.default.contents(atPath: url.path)
        switch SloDiagnosticTransaction.restoreDecision(snapshot: snapshot, current: current) {
        case .restore(let data):
            do { try runtime.grantOwnerWriteAccess(url.deletingLastPathComponent());
                try data.write(to: url, options: .atomic) }
            catch { state = .recoveryBlocked(.configChanged); return false }
        case .remove:
            do { try FileManager.default.removeItem(at: url) }
            catch { state = .recoveryBlocked(.configChanged); return false }
        case .alreadyRestored: break
        case .conflict: state = .recoveryBlocked(.configChanged); return false
        }
        snapshot.configRestored = true
        try? SloDiagnosticSnapshotStore.save(snapshot, in: applicationSupport)
        return await restoreRoots(&snapshot, runtime: runtime)
    }
    private func restoreRoots(_ snapshot: inout SloDiagnosticSnapshot,
                              runtime: SloDiagnosticRuntime) async -> Bool {
        for root in snapshot.roots.reversed() {
            if root.initiallyEnabled {
                snapshot.restoredRootFolderNames.insert(root.logicalName); continue
            }
            let initial = snapshot.modsRootURL.appendingPathComponent(root.initialPhysicalName)
            let active = snapshot.modsRootURL.appendingPathComponent(root.activePhysicalName)
            let initialExists = FileManager.default.fileExists(atPath: initial.path)
            let activeExists = FileManager.default.fileExists(atPath: active.path)
            if initialExists && !activeExists {
                snapshot.restoredRootFolderNames.insert(root.logicalName); continue
            }
            guard activeExists && !initialExists,
                  await runtime.setModEnabled(root.logicalName, false),
                  runtime.modEnabled(root.logicalName) == false else {
                state = .recoveryBlocked(.rootChanged(root.logicalName)); return false
            }
            snapshot.restoredRootFolderNames.insert(root.logicalName)
            try? SloDiagnosticSnapshotStore.save(snapshot, in: applicationSupport)
        }
        return true
    }
    private func validateRootAvailability(_ snapshot: SloDiagnosticSnapshot)
        -> SloDiagnosticRecoveryConflict? {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: snapshot.modsRootURL.path,
                                             isDirectory: &directory), directory.boolValue else {
            return .modsUnavailable
        }
        for root in snapshot.roots {
            let initial = snapshot.modsRootURL.appendingPathComponent(root.initialPhysicalName)
            let active = snapshot.modsRootURL.appendingPathComponent(root.activePhysicalName)
            if initial.path == active.path {
                if !FileManager.default.fileExists(atPath: active.path) { return .rootMissing(root.logicalName) }
                continue
            }
            let initialExists = FileManager.default.fileExists(atPath: initial.path)
            let activeExists = FileManager.default.fileExists(atPath: active.path)
            if initialExists && activeExists { return .rootCollision(root.logicalName) }
            if !initialExists && !activeExists { return .rootMissing(root.logicalName) }
        }
        return nil
    }

    private func currentConfigURL(_ snapshot: SloDiagnosticSnapshot) -> URL {
        guard let sloRoot = snapshot.roots.first(where: {
            snapshot.activeConfigURL.path.contains("/\($0.activePhysicalName)/")
        }), !sloRoot.initiallyEnabled else { return snapshot.activeConfigURL }
        let active = snapshot.modsRootURL.appendingPathComponent(sloRoot.activePhysicalName)
        return FileManager.default.fileExists(atPath: active.path)
            ? snapshot.activeConfigURL : snapshot.initialConfigURL
    }

    private func validatesNormalization(data: Data?, sha: String,
                                        log: SloDiagnosticLog) -> Bool {
        guard let data, SloDiagnosticTransaction.sha256(data) == sha,
              let value = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]),
              let object = value as? [String: Any],
              isJSONTrue(object[SloDiagnosticContract.detailedDiagnosticsKey]),
              isJSONTrue(object[SloDiagnosticContract.performanceMeasurementKey]),
              let config = log.config,
              SloOptimizerConfig.bool(config.raw["detailedDiagnostics"]) == true,
              SloOptimizerConfig.bool(config.raw["performanceMeasurement"]) == true else { return false }
        return true
    }

    private func isJSONTrue(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }

    private func modsRootURL(for installation: SloDiagnosticInstallation) -> URL {
        var root = installation.activeConfigURL.deletingLastPathComponent()
        for _ in installation.componentRelativePath.split(separator: "/") {
            root.deleteLastPathComponent()
        }
        return root.deletingLastPathComponent()
    }

    private func requireSnapshot() throws -> SloDiagnosticSnapshot {
        guard let snapshot = try SloDiagnosticSnapshotStore.load(from: applicationSupport) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return snapshot
    }

    private func orderedUnique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    private func topRoot(of folder: String, in mods: [ModItem]) -> String {
        mods.first { root in root.components.contains { $0.folderName == folder } }?.folderName
            ?? folder.split(separator: "/").first.map(String.init) ?? folder
    }
}
