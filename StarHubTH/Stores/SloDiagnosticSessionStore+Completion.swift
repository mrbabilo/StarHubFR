import CoreFoundation
import Foundation

extension SloDiagnosticSessionStore {
    func finalize(runtime: SloDiagnosticRuntime) async {
        guard !runtime.isGameRunning(), !finalizing, var snapshot = try? requireSnapshot() else { return }
        guard runtime.matches(modsRoot: snapshot.modsRootURL) else {
            setState(.recoveryBlocked(.gameDirectoryChanged)); return
        }
        finalizing = true
        defer { finalizing = false }
        setState(.restoring)
        let logData = FileManager.default.contents(atPath: logURL.path)
        let modified = (try? FileManager.default.attributesOfItem(atPath: logURL.path))?[.modificationDate] as? Date
        let logText = snapshot.launchRequestedAt.flatMap {
            SloDiagnosticSourceReader.newLog(current: logData, bookmark: snapshot.logBookmark,
                                             modified: modified, launchRequestedAt: $0)
        } ?? ""
        if kind == .stardropium {
            await finalizeMemory(snapshot: &snapshot, logText: logText, runtime: runtime)
            return
        }
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
        setReceipt(receipt)
        guard await restore(snapshot: &snapshot, runtime: runtime) else { return }
        try? SloDiagnosticSnapshotStore.clear(in: applicationSupport)
        await runtime.rescan()
        setState(.report(report))
    }
    func rollback(snapshot: SloDiagnosticSnapshot, runtime: SloDiagnosticRuntime) async -> Bool {
        var copy = snapshot
        guard await restore(snapshot: &copy, runtime: runtime) else { return false }
        if copy.configRestored && copy.restoredRootFolderNames.count == copy.roots.count {
            try? SloDiagnosticSnapshotStore.clear(in: applicationSupport)
        }
        return true
    }
    func restore(snapshot: inout SloDiagnosticSnapshot,
                         runtime: SloDiagnosticRuntime) async -> Bool {
        guard !runtime.isGameRunning() else { setState(.failed(.gameRunning)); return false }
        guard runtime.matches(modsRoot: snapshot.modsRootURL) else {
            setState(.recoveryBlocked(.gameDirectoryChanged)); return false
        }
        if let conflict = validateRootAvailability(snapshot) {
            setState(.recoveryBlocked(conflict)); return false
        }
        let url = currentConfigURL(snapshot)
        let current = FileManager.default.contents(atPath: url.path)
        switch SloDiagnosticTransaction.restoreDecision(snapshot: snapshot, current: current) {
        case .restore(let data):
            do { try runtime.grantOwnerWriteAccess(url.deletingLastPathComponent());
                try data.write(to: url, options: .atomic) }
            catch { setState(.recoveryBlocked(.configChanged)); return false }
        case .remove:
            do { try FileManager.default.removeItem(at: url) }
            catch { setState(.recoveryBlocked(.configChanged)); return false }
        case .alreadyRestored: break
        case .conflict: setState(.recoveryBlocked(.configChanged)); return false
        }
        snapshot.configRestored = true
        try? SloDiagnosticSnapshotStore.save(snapshot, in: applicationSupport)
        return await restoreRoots(&snapshot, runtime: runtime)
    }
    func restoreRoots(_ snapshot: inout SloDiagnosticSnapshot,
                              runtime: SloDiagnosticRuntime) async -> Bool {
        for root in snapshot.roots.reversed() {
            guard !runtime.isGameRunning() else { setState(.failed(.gameRunning)); return false }
            // A mod initially active may have been paused while recovery was pending.
            let enabled = DiagnosticModToggle.enabled(root: root.logicalName, modsRoot: snapshot.modsRootURL)
            if enabled == root.initiallyEnabled {
                snapshot.restoredRootFolderNames.insert(root.logicalName); continue
            }
            guard enabled != nil,
                  await runtime.setModEnabled(root.logicalName, root.initiallyEnabled),
                  runtime.modEnabled(root.logicalName) == root.initiallyEnabled else {
                setState(.recoveryBlocked(.rootChanged(root.logicalName))); return false
            }
            snapshot.restoredRootFolderNames.insert(root.logicalName)
            try? SloDiagnosticSnapshotStore.save(snapshot, in: applicationSupport)
        }
        return true
    }
    func validateRootAvailability(_ snapshot: SloDiagnosticSnapshot)
        -> SloDiagnosticRecoveryConflict? {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: snapshot.modsRootURL.path,
                                             isDirectory: &directory), directory.boolValue else {
            return .modsUnavailable
        }
        for root in snapshot.roots {
            let paused = snapshot.modsRootURL.appendingPathComponent("." + root.logicalName)
            let active = snapshot.modsRootURL.appendingPathComponent(root.activePhysicalName)
            let pausedExists = FileManager.default.fileExists(atPath: paused.path)
            let activeExists = FileManager.default.fileExists(atPath: active.path)
            if pausedExists && activeExists { return .rootCollision(root.logicalName) }
            if DiagnosticModToggle.enabled(root: root.logicalName, modsRoot: snapshot.modsRootURL) == nil {
                return .rootMissing(root.logicalName)
            }
        }
        return nil
    }

    func currentConfigURL(_ snapshot: SloDiagnosticSnapshot) -> URL {
        let configPath = snapshot.activeConfigURL.resolvingSymlinksInPath().path
        for root in snapshot.roots {
            let active = snapshot.modsRootURL.appendingPathComponent(root.activePhysicalName)
            let prefix = active.path + "/"
            guard configPath.hasPrefix(prefix) else { continue }
            if FileManager.default.fileExists(atPath: active.path) { return snapshot.activeConfigURL }
            return snapshot.modsRootURL.appendingPathComponent("." + root.logicalName)
                .appendingPathComponent(String(configPath.dropFirst(prefix.count)))
        }
        return snapshot.activeConfigURL
    }

    func validatesNormalization(data: Data?, sha: String,
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

    func isJSONTrue(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }

    func modsRootURL(for installation: SloDiagnosticInstallation) -> URL {
        var root = installation.activeConfigURL.deletingLastPathComponent()
        for _ in installation.componentRelativePath.split(separator: "/") {
            root.deleteLastPathComponent()
        }
        return root.deletingLastPathComponent()
    }

    func requireSnapshot() throws -> SloDiagnosticSnapshot {
        guard let snapshot = try SloDiagnosticSnapshotStore.load(from: applicationSupport) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return snapshot
    }

    func orderedUnique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    func topRoot(of folder: String, in mods: [ModItem]) -> String {
        mods.first { root in root.components.contains { $0.folderName == folder } }?.folderName
            ?? folder.split(separator: "/").first.map(String.init) ?? folder
    }
}

extension SloDiagnosticSessionStore {
    func finalizeMemory(snapshot: inout SloDiagnosticSnapshot, logText: String,
                        runtime: SloDiagnosticRuntime) async {
        let requested = snapshot.launchRequestedAt
        let report = await Task.detached(priority: .utility) {
            StardropiumDiagnosticReceipt.correlatedReport(log: logText, launchRequestedAt: requested)
        }.value
        let receipt = StardropiumDiagnosticReceipt(completedAt: runtime.now(), report: report)
        var reportSaved = true
        do { try receipt.save(in: applicationSupport) }
        catch { reportSaved = false }
        setMemoryReceipt(receipt)
        guard await restore(snapshot: &snapshot, runtime: runtime) else { return }
        do { try SloDiagnosticSnapshotStore.clear(in: applicationSupport) }
        catch { setState(.failed(.snapshotWrite)); return }
        await runtime.rescan()
        setState(reportSaved ? .memoryReport(report) : .failed(.snapshotWrite))
    }
}
