import Foundation

/// Manifest information extracted from manifest.json
struct ModManifest {
    let name: String
    let version: String
    let uniqueId: String
    let author: String
    let description: String
    let nexusModId: String
    let nexusUrl: String
    let dependencies: [ModDependency]
    
    init?(dict: [String: Any]) {
        guard let name = dict.caseInsensitiveValue(forKey: "Name") as? String,
              let uniqueId = dict.caseInsensitiveValue(forKey: "UniqueID") as? String else {
            return nil
        }
        
        self.name = name
        self.uniqueId = uniqueId
        
        if let author = dict.caseInsensitiveValue(forKey: "Author") as? String {
            self.author = author
        } else {
            self.author = "Unknown"
        }
        
        if let ver = dict.caseInsensitiveValue(forKey: "Version") as? String {
            self.version = ver
        } else if let verDict = dict.caseInsensitiveValue(forKey: "Version") as? [String: Any] {
            let major = verDict.caseInsensitiveValue(forKey: "MajorVersion") as? Int ?? 1
            let minor = verDict.caseInsensitiveValue(forKey: "MinorVersion") as? Int ?? 0
            let patch = verDict.caseInsensitiveValue(forKey: "PatchVersion") as? Int ?? 0
            self.version = "\(major).\(minor).\(patch)"
        } else {
            self.version = "Unknown"
        }

        self.description = dict.caseInsensitiveValue(forKey: "Description") as? String ?? ""

        // Parse Nexus mod id from UpdateKeys (mirrors VM.parseModFolder logic).
        var parsedNexusId = ""
        var parsedNexusUrl = ""
        if let updateKeys = dict.caseInsensitiveValue(forKey: "UpdateKeys") as? [String] {
            for key in updateKeys {
                if key.lowercased().hasPrefix("nexus:") {
                    var id = key.replacingOccurrences(of: "nexus:", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let atIndex = id.firstIndex(of: "@") {
                        id = String(id[..<atIndex])
                    }
                    id = id.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let num = Int(id), num > 0 {
                        parsedNexusId = id
                        parsedNexusUrl = "https://www.nexusmods.com/stardewvalley/mods/\(id)"
                        break
                    }
                }
            }
        }
        self.nexusModId = parsedNexusId
        self.nexusUrl = parsedNexusUrl
        
        var deps: [ModDependency] = []
        if let depArray = dict.caseInsensitiveValue(forKey: "Dependencies") as? [[String: Any]] {
            for dep in depArray {
                if let depId = dep.caseInsensitiveValue(forKey: "UniqueID") as? String {
                    let isReq = dep.caseInsensitiveValue(forKey: "IsRequired") as? Bool ?? true
                    deps.append(ModDependency(uniqueId: depId, isRequired: isReq))
                }
            }
        }
        self.dependencies = deps
    }
}

/// Validation status of a zip file
enum ValidationStatus {
    case valid
    case invalidStructure
    case oversized
    case tooManyMods
    case corrupted
}

/// Type of conflict detected during installation
enum ConflictType: Equatable {
    case folderExists
    case configFilesConflict
    case dependencyMissing
}

/// Available resolutions for conflicts
enum ConflictResolution: Hashable {
    case overwriteWithBackup
    case rename
    case skip
    case keepExisting
    case useNew
}

/// Conflict detected during mod installation
struct ModConflict: Identifiable {
    let id = UUID()
    let conflictType: ConflictType
    let folderName: String
    let existingVersion: String
    let newVersion: String
    let resolutionOptions: [ConflictResolution]
}

/// A single mod detected inside a zip file
struct DetectedMod: Identifiable {
    let id = UUID()
    let folderName: String
    let relativePath: String
    let manifest: ModManifest
    let hasConfigFiles: Bool
    let dependencies: [String]
    let dependencyDetails: [ModDependency]
    let existingVersion: ModItem?
    
    var uniqueId: String { manifest.uniqueId }
    var name: String { manifest.name }
    var version: String { manifest.version }
    var author: String { manifest.author }
    var nexusModId: String { manifest.nexusModId }
    var nexusUrl: String { manifest.nexusUrl }
    var modDescription: String { manifest.description }
}

/// Information extracted from a zip file before installation
struct ZipModInfo: Identifiable {
    let id = UUID()
    let zipName: String
    let detectedMods: [DetectedMod]
    let validationStatus: ValidationStatus
    let conflicts: [ModConflict]
    let estimatedSize: Int64
    
    var isValid: Bool {
        if case .valid = validationStatus {
            return true
        }
        return false
    }
    
    var hasConflicts: Bool {
        !conflicts.isEmpty
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .file)
    }
}

/// Resolution selection for a mod during installation
struct InstallSelection {
    let modId: UUID
    let selected: Bool
    let conflictResolution: ConflictResolution?
    let configResolution: ConfigResolution?
}

/// Resolution for config file conflicts
enum ConfigResolution: Hashable {
    case keepExisting
    case useNew
    case merge
}