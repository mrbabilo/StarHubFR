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
        case memoryReport(StardropiumMemoryReport)
        case recoveryBlocked(SloDiagnosticRecoveryConflict)
        case failed(SloDiagnosticFailure)
    }
    public private(set) var state: State = .idle
    public private(set) var lastReceipt: SloDiagnosticReportReceipt?
    public private(set) var memoryReceipt: StardropiumDiagnosticReceipt?
    public let kind: PerformanceDiagnosticKind
    @ObservationIgnored let exclusionDirectory: URL?
    @ObservationIgnored let applicationSupport: URL?
    @ObservationIgnored let logURL: URL
    @ObservationIgnored let probeFiles: ProbeFiles
    @ObservationIgnored var monitorTask: Task<Void, Never>?
    @ObservationIgnored var generation = 0
    @ObservationIgnored var finalizing = false
    @ObservationIgnored var pendingReport: SloDiagnosticReport?
    public init(applicationSupport: URL?, logURL: URL, probeFiles: ProbeFiles,
                kind: PerformanceDiagnosticKind = .slo) {
        self.kind = kind
        self.exclusionDirectory = applicationSupport
        self.applicationSupport = kind.directory(in: applicationSupport)
        self.logURL = logURL
        self.probeFiles = probeFiles
        self.lastReceipt = try? SloDiagnosticReportStore.load(from: self.applicationSupport)
        if kind == .stardropium {
            memoryReceipt = StardropiumDiagnosticReceipt.load(in: self.applicationSupport)
            if let report = memoryReceipt?.report { state = .memoryReport(report) }
        }
        if let report = lastReceipt?.report { state = .report(report) }
    }
    public func reload(mods: [ModItem], gameDir: URL, runtime: SloDiagnosticRuntime,
                       preserveReport: Bool = true) async {
        generation += 1
        let currentGeneration = generation
        if SloDiagnosticSnapshotStore.hasPending(in: applicationSupport) {
            if !preserveReport { await resumeIfNeeded(mods: mods, gameDir: gameDir, runtime: runtime) }
            return
        }
        if preserveReport, let report = memoryReceipt?.report {
            state = .memoryReport(report); return
        }
        if preserveReport, let report = lastReceipt?.report {
            state = .report(report)
            return
        }
        let discovery = SloDiagnosticContract.discover(mods: mods, gameDir: gameDir, kind: kind)
        var compatibility: SloDiagnosticCompatibility?
        if case .found(let installation) = discovery {
            let data = FileManager.default.contents(atPath: installation.initialConfigURL.path)
            compatibility = data == nil && FileManager.default.fileExists(atPath: installation.initialConfigURL.path)
                ? .invalidConfig
                : SloDiagnosticContract.compatibility(installation: installation, configData: data, kind: kind)
        }
        let presence = ModPresence.resolve(uniqueId: ModPresence.probeId, in: mods)
        let bundledProbeVersion = ProbeBundle.bundledFolder(resourcesURL: Bundle.main.resourceURL)
            .flatMap(ProbeBundle.version(ofFolder:))
        let action = ProbeBundle.action(bundled: bundledProbeVersion, presence: presence)
        let readiness = SloDiagnosticContract.readiness(
            discovery: discovery, compatibility: compatibility,
            probe: SloDiagnosticProbeStatus(presence: presence, action: action), nexusActivity: .idle,
            launchProfile: runtime.launchProfile(),
            busyReason: SloDiagnosticExclusion.blocksOtherPerformanceWork(snapshotDirectory: exclusionDirectory)
                ? (kind == .slo ? "stardropium-diagnostic-pending" : "slo-diagnostic-pending")
                : runtime.busyReason(), kind: kind)
        guard currentGeneration == generation else { return }
        let probeReady: Bool
        switch action {
        case .upToDate, .newerInstalled: probeReady = true
        default: probeReady = false
        }
        if case .found(let slo) = discovery, let probeFolder = presence.folderName,
           probeReady {
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
        guard !SloDiagnosticExclusion.blocksOtherPerformanceWork(snapshotDirectory: exclusionDirectory) else {
            state = .failed(.busy("diagnostic-pending")); return
        }
        state = .preparing
        let installation = preparation.slo
        guard runtime.matches(modsRoot: modsRootURL(for: installation)) else {
            state = .failed(.busy("game-directory-changed")); return
        }
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
        var initialConfigURL = modsRootURL(for: installation)
            .appendingPathComponent(sloWasEnabled ? installation.rootFolderName : "." + installation.rootFolderName)
        if !installation.componentRelativePath.isEmpty {
            initialConfigURL.appendPathComponent(installation.componentRelativePath)
        }
        initialConfigURL.appendPathComponent("config.json")
        let original = FileManager.default.contents(atPath: initialConfigURL.path)
        guard original != nil || !FileManager.default.fileExists(atPath: initialConfigURL.path) else {
            state = .failed(.invalidConfig); return
        }
        guard let prepared = try? SloDiagnosticTransaction.prepare(
            original: original, version: installation.version, kind: kind) else {
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
        guard runtime.matches(modsRoot: snapshot.modsRootURL) else {
            state = .recoveryBlocked(.gameDirectoryChanged); return
        }
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
        guard !runtime.isGameRunning() else { state = .failed(.gameRunning); return }
        guard var snapshot = try? requireSnapshot() else { return }
        guard runtime.matches(modsRoot: snapshot.modsRootURL) else {
            state = .recoveryBlocked(.gameDirectoryChanged); return
        }
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
            else if let report = memoryReceipt?.report { state = .memoryReport(report) }
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
    func setState(_ value: State) { state = value }
    func setReceipt(_ value: SloDiagnosticReportReceipt) { lastReceipt = value }
    func setMemoryReceipt(_ value: StardropiumDiagnosticReceipt) { memoryReceipt = value }
}
