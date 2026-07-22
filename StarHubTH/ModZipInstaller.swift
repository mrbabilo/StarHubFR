import Foundation

/// Handles zip file validation, analysis, extraction, and installation for mods.
///
/// Uses `/usr/bin/unzip` (same approach as `SmapiInstaller`) rather than a
/// third-party library — the app is built with plain `swiftc` (see
/// `build_app.py`) which has no SPM dependency resolution.
class ModZipInstaller {
    private let fm = FileManager.default
    private let maxZipSize: Int64 = 500 * 1024 * 1024 // 500MB
    // Caps the *uncompressed* payload a zip is allowed to expand to, checked
    // via `unzip -l` before any extraction happens. `maxZipSize` alone only
    // bounds the compressed archive on disk — a crafted zip well under that
    // cap can still compress at ~1000:1 and fill the disk once extracted.
    private let maxExtractedSize: Int64 = 2 * 1024 * 1024 * 1024 // 2GB
    private let maxModsPerZip = 10

    // MARK: - Validation

    /// Validates a zip file against size, format, and structure requirements.
    func validateZip(at url: URL) -> ValidationStatus {
        guard url.pathExtension.lowercased() == "zip" else {
            return .corrupted
        }

        var attributes: [FileAttributeKey: Any]?
        do {
            attributes = try fm.attributesOfItem(atPath: url.path)
        } catch {
            return .corrupted
        }

        guard let fileSize = attributes?[.size] as? Int64 else {
            return .corrupted
        }

        guard fileSize <= maxZipSize else {
            return .oversized
        }

        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            return .corrupted
        }
        let data = handle.readData(ofLength: 4)
        handle.closeFile()

        let signature = [0x50, 0x4B, 0x03, 0x04] // PK\03\04
        let zipSignature = [UInt8](data)
        guard zipSignature.count == 4,
              zipSignature[0] == signature[0],
              zipSignature[1] == signature[1],
              zipSignature[2] == signature[2],
              zipSignature[3] == signature[3] else {
            return .corrupted
        }

        return .valid
    }

    /// Reads the total uncompressed size an archive would expand to, via
    /// `unzip -l`'s summary line (e.g. "  1000046                     3
    /// files"), without extracting anything. Returns `nil` if the listing
    /// can't be parsed — callers should fail open in that case (rely on the
    /// post-extraction / max-mods checks) rather than block a legitimate zip
    /// on a parsing quirk.
    private func uncompressedSize(ofZipAt url: URL) -> Int64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-l", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let output = String(data: data, encoding: .utf8) else { return nil }

        for line in output.components(separatedBy: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasSuffix("files") || trimmed.hasSuffix("file") else { continue }
            let tokens = trimmed.split(separator: " ")
            if let firstToken = tokens.first, let total = Int64(firstToken) {
                return total
            }
        }
        return nil
    }

    // MARK: - Analysis

    /// Analyzes a zip file's contents and returns detailed information.
    ///
    /// The extracted temp directory is returned via the `onTempDir` callback so
    /// the caller can hold onto it for the subsequent `install()` call — the
    /// analysis pass extracts once, and install reuses that extraction rather
    /// than unzipping a second time.
    func analyzeZip(at url: URL, gameDir: String, existingMods: [ModItem], onTempDir: ((URL) -> Void)? = nil) throws -> ZipModInfo {
        let status = validateZip(at: url)
        guard case .valid = status else {
            return ZipModInfo(zipName: url.lastPathComponent, detectedMods: [], validationStatus: status, conflicts: [], estimatedSize: 0)
        }

        // Check the *uncompressed* size the archive would expand to before
        // extracting anything, so a zip-bomb never gets written to disk in
        // the first place.
        if let uncompressed = uncompressedSize(ofZipAt: url), uncompressed > maxExtractedSize {
            return ZipModInfo(zipName: url.lastPathComponent, detectedMods: [], validationStatus: .oversized, conflicts: [], estimatedSize: 0)
        }

        let tempDir = try extractToTemp(zipUrl: url)
        // NOTE: no defer cleanup here — the caller owns the temp dir through
        // `onTempDir` and must clean it up via `cleanupTempDir` when done
        // (on cancel or after install).
        onTempDir?(tempDir)

        let structure = detectZipStructure(at: tempDir)
        guard case .unrecognized = structure else {
            // proceed with a valid structure (single/multi/flatRoot)
            return buildInfo(from: tempDir, structure: structure, zipName: url.lastPathComponent, existingMods: existingMods, fallbackStatus: .valid)
                ?? ZipModInfo(zipName: url.lastPathComponent, detectedMods: [], validationStatus: .invalidStructure, conflicts: [], estimatedSize: 0)
        }
        return ZipModInfo(zipName: url.lastPathComponent, detectedMods: [], validationStatus: .invalidStructure, conflicts: [], estimatedSize: 0)
    }

    /// Builds the `ZipModInfo` by scanning the extracted temp directory
    /// according to the detected structure. Returns nil if no mod is found.
    private func buildInfo(from tempDir: URL, structure: ZipStructure, zipName: String, existingMods: [ModItem], fallbackStatus: ValidationStatus) -> ZipModInfo? {
        var detectedMods: [DetectedMod] = []
        var conflicts: [ModConflict] = []
        var totalSize: Int64 = 0

        func scanFolder(at path: URL, relativePath: String, folderName: String) {
            guard let enumerator = fm.enumerator(at: path, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
                return
            }

            var currentModManifest: ModManifest?
            // Tracks how deep the currently-adopted manifest sits relative to
            // `path`, so a shallower manifest.json always wins over one found
            // later by `FileManager.enumerator` (whose traversal order is
            // unspecified) — e.g. a bundled sub-library's nested manifest
            // must never override the real mod's top-level one.
            var currentManifestDepth = Int.max
            var hasConfigFiles = false
            var dependencies: [String] = []
            var modSize: Int64 = 0

            for case let fileURL as URL in enumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      let isRegularFile = resourceValues.isRegularFile,
                      isRegularFile else {
                    continue
                }

                if let fileSize = resourceValues.fileSize {
                    modSize += Int64(fileSize)
                }

                let filename = fileURL.lastPathComponent.lowercased()

                if filename == "manifest.json" {
                    let relative = fileURL.path.hasPrefix(path.path) ? String(fileURL.path.dropFirst(path.path.count)) : fileURL.path
                    let depth = relative.split(separator: "/").count
                    guard depth < currentManifestDepth else { continue }
                    if let data = try? Data(contentsOf: fileURL),
                       let rawString = String(data: data, encoding: .utf8) {
                        let cleanString = rawString.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
                        if let cleanData = cleanString.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: cleanData, options: [.allowFragments]) as? [String: Any],
                           let manifest = ModManifest(dict: json) {
                            currentModManifest = manifest
                            currentManifestDepth = depth
                            dependencies = manifest.dependencies.map { $0.uniqueId }
                        }
                    }
                } else if filename == "config.json" || filename == "fr.json" {
                    hasConfigFiles = true
                }
            }

            guard let manifest = currentModManifest else { return }

            let existingMod = existingMods.first { $0.uniqueId.caseInsensitiveCompare(manifest.uniqueId) == .orderedSame }

            if let existing = existingMod {
                let conflict = ModConflict(
                    conflictType: .folderExists,
                    folderName: folderName,
                    existingVersion: existing.version,
                    newVersion: manifest.version,
                    resolutionOptions: [.overwriteWithBackup, .rename, .skip]
                )
                conflicts.append(conflict)
            }

            let detectedMod = DetectedMod(
                folderName: folderName,
                relativePath: relativePath,
                manifest: manifest,
                hasConfigFiles: hasConfigFiles,
                dependencies: dependencies,
                dependencyDetails: manifest.dependencies,
                existingVersion: existingMod
            )
            detectedMods.append(detectedMod)
            totalSize += modSize
        }

        switch structure {
        case .singleMod(let baseFolder):
            let modPath = tempDir.appendingPathComponent(baseFolder)
            scanFolder(at: modPath, relativePath: baseFolder, folderName: baseFolder)
        case .multiMod(let folders):
            for folder in folders {
                let modPath = tempDir.appendingPathComponent(folder)
                scanFolder(at: modPath, relativePath: folder, folderName: folder)
            }
        case .flatRoot:
            // No enclosing folder — use the temp dir's own name as the mod
            // folder name (will become the destination folder under Mods_disabled).
            scanFolder(at: tempDir, relativePath: "", folderName: zipName.replacingOccurrences(of: ".zip", with: "", options: .caseInsensitive))
        case .unrecognized:
            return nil
        }

        guard detectedMods.count <= maxModsPerZip else {
            return ZipModInfo(zipName: zipName, detectedMods: [], validationStatus: .tooManyMods, conflicts: [], estimatedSize: 0)
        }

        guard !detectedMods.isEmpty else {
            return ZipModInfo(zipName: zipName, detectedMods: [], validationStatus: .invalidStructure, conflicts: [], estimatedSize: 0)
        }

        return ZipModInfo(
            zipName: zipName,
            detectedMods: detectedMods,
            validationStatus: .valid,
            conflicts: conflicts,
            estimatedSize: totalSize
        )
    }

    // MARK: - Structure Detection

    /// Detects the structure of extracted zip contents.
    private func detectZipStructure(at tempDir: URL) -> ZipStructure {
        var rootHasManifest = false
        var firstLevelFolders: [String] = []

        // Use subpathsOfDirectory to get paths relative to tempDir directly.
        // This avoids the symlink resolution mismatch between tempDir.path
        // (e.g. "/var/folders/...") and enumerator URL paths (e.g.
        // "/private/var/folders/...") which would corrupt string-based
        // relative-path computation.
        guard let subpaths = try? fm.subpathsOfDirectory(atPath: tempDir.path) else {
            return .unrecognized
        }

        for subpath in subpaths {
            let filename = (subpath as NSString).lastPathComponent.lowercased()
            if filename == "manifest.json" {
                let components = subpath.components(separatedBy: "/").filter { !$0.isEmpty }
                if components.count == 1 {
                    rootHasManifest = true
                } else {
                    let topLevelFolder = components.first ?? ""
                    if !firstLevelFolders.contains(topLevelFolder) {
                        firstLevelFolders.append(topLevelFolder)
                    }
                }
            }
        }

        if firstLevelFolders.count == 1 {
            return .singleMod(folderName: firstLevelFolders[0])
        } else if firstLevelFolders.count > 1 {
            return .multiMod(mods: firstLevelFolders)
        } else if rootHasManifest {
            return .flatRoot
        } else {
            return .unrecognized
        }
    }

    // MARK: - Extraction

    /// Extracts a zip archive to a directory using `/usr/bin/unzip`.
    /// Shared helper — avoids duplicating the Process boilerplate across
    /// the codebase (`SmapiInstaller` has its own copy for historical reasons).
    static func extractArchive(zipUrl: URL, to destDir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipUrl.path, "-d", destDir.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError.extractionFailed
        }
    }

    /// Extracts a zip file to a temporary directory using `/usr/bin/unzip`
    /// (mirrors `SmapiInstaller`'s approach — no external Swift dependency).
    func extractToTemp(zipUrl: URL) throws -> URL {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        // A UUID suffix keeps two analyses started within the same second
        // (e.g. dropping a second zip while the first is still analyzing)
        // from resolving to the identical temp directory, which would merge
        // two unrelated archives' contents together on extraction.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarHubTH_\(timestamp)_\(UUID().uuidString)")

        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

        do {
            try Self.extractArchive(zipUrl: zipUrl, to: tempDir)
        } catch {
            try? fm.removeItem(at: tempDir)
            throw error
        }

        // Drop macOS packaging metadata so it isn't scanned as a mod folder
        // or copied into the destination (notably for flatRoot zips, where
        // the whole temp dir is installed wholesale).
        stripMacOSXJunk(from: tempDir)

        // Reject archives containing symbolic links: `/usr/bin/unzip`
        // extracts them verbatim and a crafted link can point outside the
        // temp dir (zip-slip → arbitrary file disclosure when later read).
        do {
            try guardAgainstSymlinks(in: tempDir)
        } catch {
            try? fm.removeItem(at: tempDir)
            throw error
        }

        return tempDir
    }

    /// Removes Finder-generated `__MACOSX` metadata folders left by
    /// `/usr/bin/unzip` so they don't leak into installed mod folders.
    private func stripMacOSXJunk(from dir: URL) {
        let macosx = dir.appendingPathComponent("__MACOSX")
        if fm.fileExists(atPath: macosx.path) {
            try? fm.removeItem(at: macosx)
        }
    }

    /// Fails closed if the extracted tree contains any symbolic link.
    /// Stardew mods are plain files/folders and never require symlinks, so
    /// any link is treated as a zip-slip attempt.
    private func guardAgainstSymlinks(in dir: URL) throws {
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [] // do not skip hidden entries — malicious links can be hidden
        ) else {
            return
        }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                throw InstallError.unsafeContent
            }
        }
    }

    /// Installs selected mods from a temporary directory to the game's
    /// `Mods_disabled` folder. Applies conflict resolutions (overwrite+backup,
    /// rename, skip) and config-file resolutions (keep existing / use new)
    /// per selection.
    ///
    /// `detectedMods` is the original list from `ZipModInfo` so selections can
    /// be resolved to actual mod metadata + source paths.
    func install(from tempDir: URL, to modsDisabledPath: String, selections: [InstallSelection], detectedMods: [DetectedMod], gameDir: String, existingMods: [ModItem]) throws {
        guard !gameDir.isEmpty else { throw InstallError.gameDirEmpty }
        let backupManager = ModInstallBackupManager.shared

        try fm.createDirectory(atPath: modsDisabledPath, withIntermediateDirectories: true, attributes: nil)

        let timestampStamp = Self.stampedFolderSuffix()

        for selection in selections {
            guard selection.selected else { continue }

            guard let detectedMod = detectedMods.first(where: { $0.id == selection.modId }) else {
                continue
            }

            // Source in the temp dir: relativePath is "" for flatRoot, or the
            // subfolder name (e.g. "ContentPatcher") for single/multi mods.
            let sourcePath: URL
            if detectedMod.relativePath.isEmpty {
                sourcePath = tempDir
            } else {
                sourcePath = tempDir.appendingPathComponent(detectedMod.relativePath)
            }
            guard fm.fileExists(atPath: sourcePath.path) else { continue }

            // Resolve conflict (only relevant if a mod with the same UniqueID
            // already exists in Mods or Mods_disabled).
            let existingMod = existingMods.first { $0.uniqueId.caseInsensitiveCompare(detectedMod.uniqueId) == .orderedSame }

            let finalDestFolderName: String
            // User config files (config.json/fr.json) snapshotted from the
            // existing mod folder *before* it is removed, then restored on
            // top of the freshly installed copy. Drag-drop install must never
            // silently overwrite a user's live config.
            var preservedConfigs: [String: URL] = [:]
            if let existing = existingMod, let resolution = selection.conflictResolution {
                switch resolution {
                case .skip:
                    continue
                case .overwriteWithBackup:
                    // The backup MUST succeed before the original is ever
                    // touched — swallowing a failure here (e.g. disk full)
                    // would delete the only copy of the existing mod with no
                    // backup anywhere to recover it from.
                    do {
                        _ = try backupManager.createBackup(for: existing, gameDir: gameDir, reason: .beforeUpdate)
                    } catch {
                        throw InstallError.backupFailed(error.localizedDescription)
                    }
                    // Remove the existing folder wherever it lives (Mods or
                    // Mods_disabled) so the new copy is the only one.
                    let existingPath = (existing.isEnabled
                        ? (gameDir as NSString).appendingPathComponent("Mods")
                        : modsDisabledPath)
                    let existingFolder = (existingPath as NSString).appendingPathComponent(existing.folderName)
                    if fm.fileExists(atPath: existingFolder) {
                        preservedConfigs = snapshotUserConfigs(from: existingFolder)
                        try fm.removeItem(atPath: existingFolder)
                    }
                    finalDestFolderName = detectedMod.folderName
                case .rename:
                    finalDestFolderName = "\(detectedMod.folderName)_\(timestampStamp)"
                case .keepExisting, .useNew:
                    finalDestFolderName = detectedMod.folderName
                }
            } else {
                finalDestFolderName = detectedMod.folderName
            }

            // If the existing mod was enabled, install to Mods/ to keep it
            // enabled. New mods and previously-disabled mods go to
            // Mods_disabled/.
            let destBasePath: String
            if let existing = existingMod, existing.isEnabled, selection.conflictResolution == .overwriteWithBackup {
                destBasePath = (gameDir as NSString).appendingPathComponent("Mods")
            } else {
                destBasePath = modsDisabledPath
            }

            try fm.createDirectory(atPath: destBasePath, withIntermediateDirectories: true, attributes: nil)

            let destPath = (destBasePath as NSString).appendingPathComponent(finalDestFolderName)

            // Replace destination folder with the new mod copy.
            if fm.fileExists(atPath: destPath) {
                try fm.removeItem(atPath: destPath)
            }
            try fm.copyItem(atPath: sourcePath.path, toPath: destPath)

            // Restore preserved user configs on top of the freshly installed mod.
            for (configFile, tmp) in preservedConfigs {
                let cfg = (destPath as NSString).appendingPathComponent(configFile)
                if fm.fileExists(atPath: cfg) {
                    try? fm.removeItem(atPath: cfg)
                }
                try? fm.copyItem(atPath: tmp.path, toPath: cfg)
                try? fm.removeItem(at: tmp)
            }
        }
    }

    /// Copies `config.json`/`fr.json` from `modFolder` into temp files so
    /// they survive the folder being replaced during an overwrite install.
    private func snapshotUserConfigs(from modFolder: String) -> [String: URL] {
        var snapshots: [String: URL] = [:]
        for configFile in ["config.json", "fr.json"] {
            let cfg = (modFolder as NSString).appendingPathComponent(configFile)
            guard fm.fileExists(atPath: cfg) else { continue }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("starhubth_preserve_\(UUID().uuidString)_\(configFile)")
            do {
                try fm.copyItem(atPath: cfg, toPath: tmp.path)
                snapshots[configFile] = tmp
            } catch {
                try? fm.removeItem(at: tmp)
            }
        }
        return snapshots
    }

    /// Short timestamp suffix used for renamed duplicate mod folders.
    private static func stampedFolderSuffix() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    // MARK: - Cleanup

    /// Removes the temporary directory after installation.
    func cleanupTempDir(at url: URL) {
        try? fm.removeItem(at: url)
    }
}

// MARK: - Supporting Types

enum ZipStructure {
    case singleMod(folderName: String)
    case multiMod(mods: [String])
    case flatRoot
    case unrecognized
}

enum InstallError: LocalizedError {
    case extractionFailed
    case unsafeContent
    case gameDirEmpty
    case backupFailed(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed: return "Failed to extract zip file"
        case .unsafeContent: return "This zip contains unsafe content (symbolic links) and was rejected."
        case .gameDirEmpty: return "Game directory is not set."
        case .backupFailed(let reason): return "Backup of the existing mod failed, installation aborted: \(reason)"
        }
    }
}