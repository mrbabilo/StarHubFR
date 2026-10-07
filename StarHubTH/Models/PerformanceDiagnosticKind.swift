import Foundation

/// Shared launch/restore engine, separate configuration contracts and durable files.
public enum PerformanceDiagnosticKind: String, Sendable {
    case slo, stardropium

    public var uniqueId: String {
        self == .slo ? SloDiagnosticContract.uniqueId : "Arshia1381.Stardropium"
    }
    public var nexusId: Int { self == .slo ? SloDiagnosticContract.nexusId : 52803 }
    public var minimumVersion: [Int] { self == .slo ? SloDiagnosticContract.minimumVersion : [0, 2, 2] }
    public func supports(version: String) -> Bool {
        // Stardropium's audited release is explicitly 0.2.2-beta.
        let core = self == .stardropium
            ? String(version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? "") : version
        return ProbeLoadRecords.version(core, atLeast: minimumVersion)
    }
    public var enabledKeys: [String] {
        self == .slo
            ? [SloDiagnosticContract.detailedDiagnosticsKey, SloDiagnosticContract.performanceMeasurementKey]
            : ["EnableMemoryOptimization", "AutoTrimWorkingSetOnNewDay"]
    }
    public func directory(in root: URL?) -> URL? {
        self == .slo ? root : root?.appendingPathComponent("StardropiumDiagnostic", isDirectory: true)
    }
}

public struct StardropiumDiagnosticReceipt: Codable, Equatable, Sendable {
    public let completedAt: Date
    public let report: StardropiumMemoryReport

    public static func correlatedReport(log: String, launchRequestedAt: Date?) -> StardropiumMemoryReport {
        let report = StardropiumMemoryReport.parse(log)
        guard let requested = launchRequestedAt, let start = report.sessionStart,
              start >= requested.addingTimeInterval(-5),
              start <= requested.addingTimeInterval(90) else { return .init() }
        return report
    }

    public static func load(in directory: URL?) -> Self? {
        guard let directory else { return nil }
        do {
            return try JSONDecoder().decode(Self.self, from: Data(contentsOf:
                directory.appendingPathComponent("memory_report.json")))
        } catch { return nil }
    }

    public func save(in directory: URL?) throws {
        guard let directory else { throw SloDiagnosticSnapshotStoreError.missingDirectory }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent("memory_report.json"), options: .atomic)
    }
}
