import Foundation

public enum SloDiagnosticExclusionError: Error, Equatable, Sendable {
    case diagnosticPending
}

public enum SloDiagnosticExclusion {
    public static func blocksOtherPerformanceWork(snapshotDirectory: URL?) -> Bool {
        SloDiagnosticSnapshotStore.hasPending(in: snapshotDirectory)
    }

    public static func busyReason(gameRunning: Bool, benchmarkActive: Bool,
                                  bisectionActive: Bool, guidedPlanPending: Bool,
                                  otherReason: String?) -> String? {
        if gameRunning { return "game-running" }
        if benchmarkActive { return "benchmark-running" }
        if bisectionActive { return "bisection-running" }
        if guidedPlanPending { return "guided-measurement-pending" }
        return otherReason
    }
}

public extension SloDiagnosticSnapshotStore {
    static func hasPending(in directory: URL?) -> Bool {
        guard let directory else { return false }
        return FileManager.default.fileExists(atPath: fileURL(in: directory).path)
    }
}

@MainActor
public struct SloDiagnosticRuntime {
    public static let pollSeconds: TimeInterval = 5
    public static let launchTimeout: TimeInterval = 90
    public static let sourceSettleSeconds: TimeInterval = 3
    public let isGameRunning: () -> Bool
    public let busyReason: () -> String?
    public let launchProfile: () -> String
    public let modEnabled: (String) -> Bool?
    public let setModEnabled: (String, Bool) async -> Bool
    public let grantOwnerWriteAccess: (URL) throws -> Void
    public let launchGame: () -> Bool
    public let rescan: () async -> Void
    public let now: () -> Date
    public let sleep: (TimeInterval) async -> Void

    public init(isGameRunning: @escaping () -> Bool,
                busyReason: @escaping () -> String?, launchProfile: @escaping () -> String,
                modEnabled: @escaping (String) -> Bool?,
                setModEnabled: @escaping (String, Bool) async -> Bool,
                grantOwnerWriteAccess: @escaping (URL) throws -> Void,
                launchGame: @escaping () -> Bool, rescan: @escaping () async -> Void,
                now: @escaping () -> Date = Date.init,
                sleep: @escaping (TimeInterval) async -> Void = { seconds in
                    try? await Task.sleep(for: .seconds(seconds))
                }) {
        self.isGameRunning = isGameRunning; self.busyReason = busyReason
        self.launchProfile = launchProfile; self.modEnabled = modEnabled
        self.setModEnabled = setModEnabled; self.grantOwnerWriteAccess = grantOwnerWriteAccess
        self.launchGame = launchGame; self.rescan = rescan; self.now = now; self.sleep = sleep
    }
}

public struct SloDiagnosticPreparation: Equatable, Sendable {
    public let slo: SloDiagnosticInstallation
    public let probeRootFolderName: String
    public let probeWasEnabled: Bool

    public init(slo: SloDiagnosticInstallation, probeRootFolderName: String,
                probeWasEnabled: Bool) {
        self.slo = slo; self.probeRootFolderName = probeRootFolderName
        self.probeWasEnabled = probeWasEnabled
    }
}

public struct SloDiagnosticReportReceipt: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let completedAt: Date
    public let sessionId: String?
    public let report: SloDiagnosticReport
    public let sourceFingerprints: [String: String]

    public init(completedAt: Date, sessionId: String?, report: SloDiagnosticReport,
                sourceFingerprints: [String: String]) {
        self.formatVersion = 1; self.completedAt = completedAt; self.sessionId = sessionId
        self.report = report; self.sourceFingerprints = sourceFingerprints
    }
}

public enum SloDiagnosticReportStore {
    public static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("slo_diagnostic_report.json")
    }

    public static func save(_ receipt: SloDiagnosticReportReceipt, in directory: URL?) throws {
        guard let directory else { throw SloDiagnosticSnapshotStoreError.missingDirectory }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(receipt).write(to: fileURL(in: directory), options: .atomic)
    }

    public static func load(from directory: URL?) throws -> SloDiagnosticReportReceipt? {
        guard let directory else { return nil }
        let url = fileURL(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let receipt = try JSONDecoder().decode(SloDiagnosticReportReceipt.self,
                                               from: Data(contentsOf: url))
        guard receipt.formatVersion == 1 else {
            throw SloDiagnosticSnapshotStoreError.unsupportedFormat(receipt.formatVersion)
        }
        return receipt
    }

    public static func clear(in directory: URL?) throws {
        guard let directory else { return }
        let url = fileURL(in: directory)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

public enum SloDiagnosticRecoveryConflict: Equatable, Sendable {
    case modsUnavailable, configChanged
    case rootMissing(String), rootCollision(String), rootChanged(String)
}

public enum SloDiagnosticFailure: Equatable, Sendable {
    case vanillaProfile, gameRunning, snapshotWrite, invalidConfig, configWrite, launch
    case busy(String), rootActivation(String), snapshotUnreadable
}
