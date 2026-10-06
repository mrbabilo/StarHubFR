import CoreFoundation
import Foundation

public struct SloDiagnosticInstallation: Equatable, Sendable {
    public let rootFolderName: String
    public let rootPhysicalFolderName: String
    public let activeRootPhysicalFolderName: String
    public let componentRelativePath: String
    public let version: String
    public let isEnabled: Bool
    public let initialConfigURL: URL
    public let activeConfigURL: URL
    public let activatedSiblingNames: [String]

    public init(rootFolderName: String, rootPhysicalFolderName: String,
                activeRootPhysicalFolderName: String, componentRelativePath: String,
                version: String, isEnabled: Bool, initialConfigURL: URL,
                activeConfigURL: URL, activatedSiblingNames: [String]) {
        self.rootFolderName = rootFolderName
        self.rootPhysicalFolderName = rootPhysicalFolderName
        self.activeRootPhysicalFolderName = activeRootPhysicalFolderName
        self.componentRelativePath = componentRelativePath
        self.version = version
        self.isEnabled = isEnabled
        self.initialConfigURL = initialConfigURL
        self.activeConfigURL = activeConfigURL
        self.activatedSiblingNames = activatedSiblingNames
    }
}

public enum SloDiagnosticDiscovery: Equatable, Sendable {
    case absent
    case found(SloDiagnosticInstallation)
    case ambiguous([String])
}

public enum SloDiagnosticCompatibility: Equatable, Sendable {
    case compatible
    case outdated(String)
    case missingConfig
    case invalidConfig
}

public struct SloDiagnosticProbeStatus: Equatable, Sendable {
    public let presence: ModPresence
    public let action: ProbeBundle.Action

    public init(presence: ModPresence, action: ProbeBundle.Action) {
        self.presence = presence
        self.action = action
    }
}

public enum SloDiagnosticNexusActivity: Equatable, Sendable {
    case idle
    case downloading(modId: Int)
    case awaitingInstall(modId: Int)
}

public enum SloDiagnosticReadiness: Equatable, Sendable {
    case sloAbsent
    case sloDownloading
    case sloPaused(SloDiagnosticInstallation)
    case ready(SloDiagnosticInstallation)
    case incompatible(String)
    case ambiguous([String])
    case probeInstallRequired(ProbeBundle.Action)
    case probePaused
    case blocked(String)
}

public enum SloDiagnosticInstallRoute: Equatable, Sendable {
    case directDownload(Int)
    case webPage(URL)
}

/// Contrat pur entre scan des mods et session diagnostique SLO.
public enum SloDiagnosticContract {
    public static let uniqueId = "neoiw.StardewLoadingOptimizer"
    public static let nexusId = 50153
    public static let minimumVersion = [1, 0, 0]
    public static let detailedDiagnosticsKey = "EnableDetailedDiagnostics"
    public static let performanceMeasurementKey = "EnablePerformanceMeasurement"

    public static func discover(mods: [ModItem], gameDir: URL) -> SloDiagnosticDiscovery {
        let wanted = uniqueId.lowercased()
        var matches: [SloDiagnosticInstallation] = []

        for root in mods {
            for component in root.components where component.uniqueId.lowercased() == wanted {
                let relativePath = componentPath(component.folderName, under: root.folderName)
                let initial = configURL(gameDir: gameDir, root: root.physicalFolderName,
                                        component: relativePath)
                let active = configURL(gameDir: gameDir, root: root.folderName,
                                       component: relativePath)
                let siblings: [String]
                if root.isGroup, !root.isEnabled {
                    siblings = root.components
                        .filter { $0.folderName != component.folderName }
                        .map(\.name)
                        .sorted()
                } else {
                    siblings = []
                }
                matches.append(SloDiagnosticInstallation(
                    rootFolderName: root.folderName,
                    rootPhysicalFolderName: root.physicalFolderName,
                    activeRootPhysicalFolderName: root.folderName,
                    componentRelativePath: relativePath,
                    version: component.version,
                    isEnabled: root.isEnabled && component.isEnabled,
                    initialConfigURL: initial,
                    activeConfigURL: active,
                    activatedSiblingNames: siblings
                ))
            }
        }

        if matches.isEmpty { return .absent }
        if matches.count > 1 {
            return .ambiguous(matches.map { installation in
                installation.componentRelativePath.isEmpty
                    ? installation.rootFolderName
                    : installation.rootFolderName + "/" + installation.componentRelativePath
            }.sorted())
        }
        return .found(matches[0])
    }

    public static func compatibility(installation: SloDiagnosticInstallation,
                                     configData: Data?) -> SloDiagnosticCompatibility {
        guard ProbeLoadRecords.version(installation.version, atLeast: minimumVersion) else {
            return .outdated(installation.version)
        }
        guard let configData else { return .missingConfig }
        guard let value = try? JSONSerialization.jsonObject(with: configData, options: [.json5Allowed]),
              let object = value as? [String: Any]
        else { return .invalidConfig }
        for key in [detailedDiagnosticsKey, performanceMeasurementKey] {
            if let value = object[key], !isJSONBoolean(value) { return .invalidConfig }
        }
        return .compatible
    }

    public static func readiness(discovery: SloDiagnosticDiscovery,
                                 compatibility: SloDiagnosticCompatibility?,
                                 probe: SloDiagnosticProbeStatus,
                                 nexusActivity: SloDiagnosticNexusActivity,
                                 launchProfile: String,
                                 busyReason: String?) -> SloDiagnosticReadiness {
        if let busyReason, !busyReason.isEmpty { return .blocked(busyReason) }
        if launchProfile == "Vanilla" { return .blocked("vanilla") }

        switch nexusActivity {
        case .downloading(let modId), .awaitingInstall(let modId):
            if modId == nexusId { return .sloDownloading }
            return .blocked("nexus-busy")
        case .idle:
            break
        }

        let installation: SloDiagnosticInstallation
        switch discovery {
        case .absent:
            return .sloAbsent
        case .ambiguous(let folders):
            return .ambiguous(folders)
        case .found(let found):
            installation = found
        }

        switch compatibility {
        case .outdated(let version): return .incompatible("outdated:\(version)")
        case .invalidConfig: return .incompatible("invalid-config")
        case nil: return .blocked("compatibility-unknown")
        case .compatible, .missingConfig: break
        }

        switch probe.action {
        case .unavailable, .install, .update:
            return .probeInstallRequired(probe.action)
        case .upToDate, .newerInstalled:
            if case .paused = probe.presence { return .probePaused }
        }

        return installation.isEnabled ? .ready(installation) : .sloPaused(installation)
    }

    public static func installRoute(directDownloadUnavailable: Bool) -> SloDiagnosticInstallRoute {
        directDownloadUnavailable
            ? .webPage(MissingDependencies.filesPage(nexusId: nexusId))
            : .directDownload(nexusId)
    }

    private static func componentPath(_ folderName: String, under rootFolderName: String) -> String {
        guard folderName != rootFolderName else { return "" }
        let prefix = rootFolderName + "/"
        guard folderName.hasPrefix(prefix) else { return folderName }
        return String(folderName.dropFirst(prefix.count))
    }

    private static func configURL(gameDir: URL, root: String, component: String) -> URL {
        var url = gameDir.appendingPathComponent("Mods", isDirectory: true)
            .appendingPathComponent(root, isDirectory: true)
        if !component.isEmpty { url.appendPathComponent(component, isDirectory: true) }
        return url.appendingPathComponent("config.json")
    }

    private static func isJSONBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
