import CoreFoundation
import CryptoKit
import Foundation

public enum SloDiagnosticConfigState: Codable, Equatable, Sendable {
    case missing
    case bytes(Data)
}

public struct SloDiagnosticLogBookmark: Codable, Equatable, Sendable {
    public let size: Int
    public let sha256: String
    public let modified: Date?

    public init(size: Int, sha256: String, modified: Date?) {
        self.size = size
        self.sha256 = sha256
        self.modified = modified
    }
}

public struct SloDiagnosticRootSnapshot: Codable, Equatable, Sendable {
    public let logicalName: String
    public let initialPhysicalName: String
    public let activePhysicalName: String
    public let initiallyEnabled: Bool

    public init(logicalName: String, initialPhysicalName: String,
                activePhysicalName: String, initiallyEnabled: Bool) {
        self.logicalName = logicalName
        self.initialPhysicalName = initialPhysicalName
        self.activePhysicalName = activePhysicalName
        self.initiallyEnabled = initiallyEnabled
    }
}

/// Autorité durable d'une transaction : chaque frontière est enregistrée
/// avant de passer à la suivante, afin que la reprise reste idempotente.
public struct SloDiagnosticSnapshot: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let id: UUID
    public let startedAt: Date
    public var launchRequestedAt: Date?
    public var gameSeen: Bool
    public let modsRootURL: URL
    public let roots: [SloDiagnosticRootSnapshot]
    public let initialConfigURL: URL
    public let activeConfigURL: URL
    public let originalConfig: SloDiagnosticConfigState
    public let diagnosticConfig: Data
    public var acceptedDiagnosticSHA256: Set<String>
    public let logBookmark: SloDiagnosticLogBookmark?
    public let knownProbeSessionIDs: Set<String>
    public var activatedRootFolderNames: Set<String>
    public var configWritten: Bool
    public var configRestored: Bool
    public var restoredRootFolderNames: Set<String>

    public init(id: UUID = UUID(), startedAt: Date, launchRequestedAt: Date? = nil,
                gameSeen: Bool = false, modsRootURL: URL,
                roots: [SloDiagnosticRootSnapshot], initialConfigURL: URL,
                activeConfigURL: URL, originalConfig: SloDiagnosticConfigState,
                diagnosticConfig: Data, acceptedDiagnosticSHA256: Set<String>,
                logBookmark: SloDiagnosticLogBookmark?, knownProbeSessionIDs: Set<String>,
                activatedRootFolderNames: Set<String> = [], configWritten: Bool = false,
                configRestored: Bool = false, restoredRootFolderNames: Set<String> = []) {
        self.formatVersion = 1
        self.id = id
        self.startedAt = startedAt
        self.launchRequestedAt = launchRequestedAt
        self.gameSeen = gameSeen
        self.modsRootURL = modsRootURL.resolvingSymlinksInPath()
        var seen = Set<String>()
        self.roots = roots.filter { seen.insert($0.logicalName.lowercased()).inserted }
        self.initialConfigURL = initialConfigURL
        self.activeConfigURL = activeConfigURL
        self.originalConfig = originalConfig
        self.diagnosticConfig = diagnosticConfig
        var accepted = acceptedDiagnosticSHA256
        accepted.insert(SloDiagnosticTransaction.sha256(diagnosticConfig))
        self.acceptedDiagnosticSHA256 = accepted
        self.logBookmark = logBookmark
        self.knownProbeSessionIDs = knownProbeSessionIDs
        self.activatedRootFolderNames = activatedRootFolderNames
        self.configWritten = configWritten
        self.configRestored = configRestored
        self.restoredRootFolderNames = restoredRootFolderNames
    }
}

public struct SloDiagnosticPreparedConfig: Equatable, Sendable {
    public let data: Data
    public let original: SloDiagnosticConfigState
    public let sha256: String
}

public enum SloDiagnosticRestoreDecision: Equatable, Sendable {
    case restore(Data)
    case remove
    case alreadyRestored
    case conflict
}

public enum SloDiagnosticTransactionError: Error, Equatable, Sendable {
    case outdatedVersion(String)
    case invalidConfig
    case invalidDiagnosticValue(String)
}

public enum SloDiagnosticTransaction {
    public static func prepare(original: Data?, version: String) throws -> SloDiagnosticPreparedConfig {
        guard ProbeLoadRecords.version(version, atLeast: SloDiagnosticContract.minimumVersion) else {
            throw SloDiagnosticTransactionError.outdatedVersion(version)
        }

        let originalState = original.map(SloDiagnosticConfigState.bytes) ?? .missing
        let object: [String: Any]
        if let original, !original.isEmpty {
            guard let decoded = try? JSONSerialization.jsonObject(with: original,
                                                                  options: [.json5Allowed]),
                  let dictionary = decoded as? [String: Any]
            else { throw SloDiagnosticTransactionError.invalidConfig }
            object = dictionary
        } else {
            object = [:]
        }

        var prepared = object
        for key in [SloDiagnosticContract.detailedDiagnosticsKey,
                    SloDiagnosticContract.performanceMeasurementKey] {
            if let value = prepared[key], !isJSONBoolean(value) {
                throw SloDiagnosticTransactionError.invalidDiagnosticValue(key)
            }
            prepared[key] = true
        }
        guard JSONSerialization.isValidJSONObject(prepared) else {
            throw SloDiagnosticTransactionError.invalidConfig
        }
        let data = try JSONSerialization.data(withJSONObject: prepared,
                                              options: [.prettyPrinted, .sortedKeys])
        return SloDiagnosticPreparedConfig(data: data, original: originalState, sha256: sha256(data))
    }

    public static func restoreDecision(snapshot: SloDiagnosticSnapshot,
                                       current: Data?) -> SloDiagnosticRestoreDecision {
        switch snapshot.originalConfig {
        case .missing:
            guard let current else { return .alreadyRestored }
            return snapshot.acceptedDiagnosticSHA256.contains(sha256(current)) ? .remove : .conflict
        case .bytes(let original):
            if current == original { return .alreadyRestored }
            guard let current,
                  snapshot.acceptedDiagnosticSHA256.contains(sha256(current))
            else { return .conflict }
            return .restore(original)
        }
    }

    public static func currentConfigURL(snapshot: SloDiagnosticSnapshot,
                                        rootIsEnabled: Bool) -> URL {
        rootIsEnabled ? snapshot.activeConfigURL : snapshot.initialConfigURL
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isJSONBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}

public enum SloDiagnosticSnapshotStoreError: Error, Equatable, Sendable {
    case missingDirectory
    case unsupportedFormat(Int)
}

public enum SloDiagnosticSnapshotStore {
    public static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("slo_diagnostic_snapshot.json")
    }

    public static func save(_ snapshot: SloDiagnosticSnapshot, in directory: URL?) throws {
        guard let directory else { throw SloDiagnosticSnapshotStoreError.missingDirectory }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL(in: directory), options: .atomic)
    }

    public static func load(from directory: URL?) throws -> SloDiagnosticSnapshot? {
        guard let directory else { return nil }
        let url = fileURL(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let snapshot = try JSONDecoder().decode(SloDiagnosticSnapshot.self, from: Data(contentsOf: url))
        guard snapshot.formatVersion == 1 else {
            throw SloDiagnosticSnapshotStoreError.unsupportedFormat(snapshot.formatVersion)
        }
        return snapshot
    }

    public static func clear(in directory: URL?) throws {
        guard let directory else { return }
        let url = fileURL(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
