import Foundation

/// Handles zip file validation, analysis, extraction, and installation for mods.
///
/// Uses `/usr/bin/unzip` (same approach as `SmapiInstaller`) rather than a
/// third-party library — the app is built with plain `swiftc` (see
/// `build_app.py`) which has no SPM dependency resolution.
class ModZipInstaller {
    private let fm = FileManager.default
    private let maxZipSize: Int64 = 500 * 1024 * 1024 // 500MB

    /// Finds an installed mod whose `uniqueId` matches `targetUniqueId`,
    /// searching both top-level mods and the `children` of pack groups.
    /// Pack group headers have an empty `uniqueId`, so a flat top-level
    /// search would miss mods that are part of a multi-mod pack — this
    /// resolves that so updates of packed mods are correctly detected as
    /// conflicts.
    private func findExistingMod(_ uniqueId: String, in mods: [ModItem]) -> ModItem? {
        for mod in mods {
            if !mod.uniqueId.isEmpty
                && mod.uniqueId.caseInsensitiveCompare(uniqueId) == .orderedSame {
                return mod
            }
            if let children = mod.children {
                if let child = children.first(where: {
                    !$0.uniqueId.isEmpty
                        && $0.uniqueId.caseInsensitiveCompare(uniqueId) == .orderedSame
                }) {
                    return child
                }
            }
        }
        return nil
    }
    // Caps the *uncompressed* payload a zip is allowed to expand to, checked
    // via `unzip -l` before any extraction happens. `maxZipSize` alone only
    // bounds the compressed archive on disk — a crafted zip well under that
    // cap can still compress at ~1000:1 and fill the disk once extracted.
    private let maxExtractedSize: Int64 = 2 * 1024 * 1024 * 1024 // 2GB
    private let maxModsPerZip = 10

    /// Format réel d'une archive, déduit de sa signature — la seule source
    /// fiable. Le nom d'un fichier peut mentir ou ne rien dire : l'URL de
    /// téléchargement gratuit de Nexus, notamment, ne porte pas toujours
    /// d'extension exploitable, ce qui faisait enregistrer un `.7z` sous
    /// « .zip » et échouer l'extraction.
    static func archiveExtension(forSignature bytes: [UInt8]) -> String? {
        func starts(_ sig: [UInt8]) -> Bool {
            bytes.count >= sig.count && Array(bytes.prefix(sig.count)) == sig
        }
        if starts([0x50, 0x4B, 0x03, 0x04]) { return "zip" }
        if starts([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]) { return "rar" }
        if starts([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return "7z" }
        return nil
    }

    /// Lit les premiers octets d'un fichier pour en déduire le format.
    static func detectedArchiveExtension(at url: URL) -> String? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { handle.closeFile() }
        return archiveExtension(forSignature: [UInt8](handle.readData(ofLength: 8)))
    }

    /// Retire l'extension d'archive d'un nom de fichier, pour en tirer un nom de
    /// dossier propre.
    static func strippingArchiveExtension(from name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return name }
        return (name as NSString).deletingPathExtension
    }

    /// Formats d'archive acceptés à l'installation. Le `.7z` est courant sur
    /// Nexus ; avant son ajout, toute extension inconnue était rejetée comme
    /// « archive corrompue », ce qui envoyait l'utilisateur chercher un problème
    /// qui n'existait pas.
    static let supportedExtensions: Set<String> = ["zip", "rar", "7z"]

    // MARK: - Validation
    /// Validates an archive file against size, format, and structure requirements.
    /// Supports `.zip`, `.rar` and `.7z`.
    func validateZip(at url: URL) -> ValidationStatus {
        let ext = url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            return .unsupportedFormat(ext)
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

        // Verify the file signature matches the declared extension.
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            return .corrupted
        }
        let data = handle.readData(ofLength: 8)
        handle.closeFile()

        let bytes = [UInt8](data)
        if ext == "zip" {
            // ZIP signature: PK\x03\x04
            let sig: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
            guard bytes.count >= 4,
                  bytes[0] == sig[0], bytes[1] == sig[1],
                  bytes[2] == sig[2], bytes[3] == sig[3] else {
                return .corrupted
            }
        } else if ext == "rar" {
            // RAR signature: "Rar!\x1a\x07" (common to RAR4 and RAR5).
            let sig: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]
            guard bytes.count >= 6, Array(bytes.prefix(6)) == sig else {
                return .corrupted
            }
        } else {
            // 7z signature: "7z\xbc\xaf\x27\x1c".
            let sig: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]
            guard bytes.count >= 6, Array(bytes.prefix(6)) == sig else {
                return .corrupted
            }
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
        // Force the C locale so the summary line we parse below always says
        // "N files" regardless of the user's UI language. Without this a French
        // locale ("N fichiers") would make `uncompressedSize` return nil and
        // silently disable the zip-bomb guard.
        process.environment = Self.cLocaleEnvironment
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

        return analyzeExtractedDir(at: tempDir, zipName: url.lastPathComponent, existingMods: existingMods)
    }

    /// Analyzes an already-extracted temp directory: detects the archive
    /// structure and builds the `ZipModInfo`. Split out from `analyzeZip` so
    /// the structure detection (including multi-component pack grouping) is
    /// unit-testable without building a real archive — tests lay out a temp
    /// dir of mod folders and call this directly.
    func analyzeExtractedDir(at tempDir: URL, zipName: String, existingMods: [ModItem]) -> ZipModInfo {
        let structure = detectZipStructure(at: tempDir)
        guard case .unrecognized = structure else {
            // proceed with a valid structure (single/multi/flatRoot)
            return buildInfo(from: tempDir, structure: structure, zipName: zipName, existingMods: existingMods, fallbackStatus: .valid)
                ?? ZipModInfo(zipName: zipName, detectedMods: [], validationStatus: .invalidStructure, conflicts: [], estimatedSize: 0)
        }
        return ZipModInfo(zipName: zipName, detectedMods: [],
                          validationStatus: .invalidStructure,
                          extractedTopLevel: Self.topLevelSummary(of: tempDir),
                          conflicts: [], estimatedSize: 0)
    }

    /// Ce que l'archive contenait réellement, résumé pour l'affichage.
    ///
    /// « manifest.json manquant » n'apprend rien : la détection parcourt toute
    /// l'arborescence, donc l'utilisateur sait seulement qu'il n'y en avait
    /// nulle part — sans savoir ce qu'il y avait à la place. Or la cause est
    /// souvent visible d'un coup d'œil : une archive qui en contient d'autres,
    /// des fichiers à copier à la main, une documentation seule.
    static func topLevelSummary(of dir: URL) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return entries.filter { !$0.hasPrefix(".") }.sorted().prefix(12).map { name in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path,
                                           isDirectory: &isDir)
            return isDir.boolValue ? "\(name)/" : name
        }
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
                           // No `.allowFragments` here: a manifest MUST be a JSON object — accepting
                            // a top-level scalar would mask a genuinely corrupt file.
                            let json = try? JSONSerialization.jsonObject(with: cleanData) as? [String: Any],
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

            let existingMod = findExistingMod(manifest.uniqueId, in: existingMods)

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
            // When every component lives under the same single top-level
            // folder in the zip (a genuine pack — e.g. "Lilybrook/[CC]",
            // "Lilybrook/[CP]", "Lilybrook/[FTM]"), preserve that parent so
            // each component installs under Mods/<Parent>/<leaf>. The mod-list
            // scanner groups any top-level folder holding several manifests
            // into one pack entry, so a grouped on-disk layout makes the pack
            // appear as a single entry — matching what the user downloaded.
            // Flat collections (no shared parent) keep one-folder-per-component.
            let sharedParent = Self.commonParent(of: folders)
            for folder in folders {
                let modPath = tempDir.appendingPathComponent(folder)
                let leaf = (folder as NSString).lastPathComponent
                let destFolderName = sharedParent.map { "\($0)/\(leaf)" } ?? leaf
                scanFolder(at: modPath, relativePath: folder, folderName: destFolderName)
            }
        case .flatRoot:
            // No enclosing folder — use the temp dir's own name as the mod
            // folder name (will become the destination folder under Mods/ as
            // `.<name>` when disabled by default).
            // Retirer l'extension quelle qu'elle soit : ne traiter que « .zip »
            // donnait un dossier nommé « MonMod.7z » sous Mods/.
            scanFolder(at: tempDir, relativePath: "",
                       folderName: Self.strippingArchiveExtension(from: zipName))
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

    /// Returns the single top-level parent folder shared by every entry, or
    /// nil when the entries sit at the zip root or disagree. "Lilybrook" for
    /// "Lilybrook/[CP] Lilybrook"; nil for a flat collection ("[C1]", "[C2]")
    /// or a mix of nested and root entries.
    private static func commonParent(of folders: [String]) -> String? {
        let parents = folders.map { ($0 as NSString).deletingLastPathComponent }
        guard parents.allSatisfy({ !$0.isEmpty }) else { return nil }
        let unique = Set(parents)
        return unique.count == 1 ? unique.first : nil
    }

    /// Detects the structure of extracted zip contents.
    private func detectZipStructure(at tempDir: URL) -> ZipStructure {
        var rootHasManifest = false
        /// Dossiers contenant directement un `manifest.json`, indexés par
        /// leur chemin relatif depuis `tempDir`. Une même clé peut pointer
        /// vers un mod unique (ex. `["Parchment"]`) ou vers plusieurs mods
        /// encapsulés dans un dossier racine (ex. `["Parchment/Parchment",
        /// "Parchment/[CP] ..."]`). On conserve le chemin complet pour
        /// pouvoir distinguer les structures imbriquées.
        var manifestFolders: [String] = []

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
                    // manifest.json directement à la racine du tempDir.
                    rootHasManifest = true
                } else {
                    // Le dossier conteneur du manifest est le composant juste
                    // avant "manifest.json". On conserve le chemin relatif
                    // complet jusqu'à ce dossier (ex. "Parchment/Parchment"),
                    // ce qui préserve la structure d'encapsulation.
                    let parentPath = components.dropLast().joined(separator: "/")
                    if !manifestFolders.contains(parentPath) {
                        manifestFolders.append(parentPath)
                    }
                }
            }
        }

        // A manifest nested under another manifest folder is a bundled
        // dependency (e.g. "MyMod/lib/SomeDep/manifest.json" under
        // "MyMod/manifest.json"), not a sibling mod. Drop it so it isn't
        // installed as a separate top-level folder (which would also create
        // stray duplicate-mod conflicts when the same dependency is already
        // installed standalone). Order-independent: checks all ancestor pairs.
        manifestFolders = manifestFolders.filter { folder in
            !manifestFolders.contains { other in
                other != folder && folder.hasPrefix(other + "/")
            }
        }

        // Cas 1 : un seul dossier de mod, directement à la racine (ex.
        // "ContentPatcher/manifest.json") → singleMod avec ce dossier.
        // Cas 2 : plusieurs dossiers de mod partageant le même dossier racine
        // d'encapsulation (ex. "Parchment/Parchment" +
        // "Parchment/[CP] ...") → multiMod avec les sous-dossiers.
        // Cas 3 : plusieurs dossiers de mod à la racine → multiMod.
        let topLevelFolders = Set(manifestFolders.map { $0.split(separator: "/").first.map(String.init) ?? $0 })
        if manifestFolders.count == 1 && topLevelFolders.count == 1 {
            return .singleMod(folderName: manifestFolders[0])
        } else if manifestFolders.count > 1 {
            return .multiMod(mods: manifestFolders)
        } else if rootHasManifest {
            return .flatRoot
        } else {
            return .unrecognized
        }
    }

    // MARK: - Extraction

    /// Extracts an archive (`.zip` or `.rar`) to a directory.
    /// - ZIP: uses `/usr/bin/unzip` (always available on macOS).
    /// - RAR: uses the first available of `unrar`, `unar`, or `7z`
    ///   (not bundled — checked at runtime). Throws `rarToolMissing` if none
    ///   is found.
    static func extractArchive(zipUrl: URL, to destDir: URL) throws {
        let ext = zipUrl.pathExtension.lowercased()

        if ext == "zip" {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", zipUrl.path, "-d", destDir.path]
            // Force the C locale so error/diagnostic output stays parseable
            // (the summary line is what we read in `uncompressedSize`; keeping
            // extraction under the same locale makes the two consistent).
            process.environment = Self.cLocaleEnvironment
            try process.run()
            process.waitUntilExit()
            guard Self.isTolerableExitStatus(process.terminationStatus) else {
                throw InstallError.extractionFailed
            }
        } else {
            // .rar et .7z passent par un outil externe. `unrar` ne lit pas le
            // 7z, d'où deux listes de préférence distinctes.
            guard let tool = ext == "rar" ? Self.findRarTool() : Self.find7zTool() else {
                throw InstallError.rarToolMissing
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool.path)
            process.arguments = tool.arguments(zipUrl.path, destDir.path)
            process.environment = Self.cLocaleEnvironment
            try process.run()
            process.waitUntilExit()
            guard Self.isTolerableExitStatus(process.terminationStatus) else {
                throw InstallError.extractionFailed
            }
        }

        // Status 1 means "extracted, but with warnings" — we accepted it above,
        // so the real proof of success is the content on disk. An archive that
        // warns *and* yields nothing is a genuine failure, and catching it here
        // keeps the user on "extraction failed" instead of the misleading
        // "no valid mod structure" the scan would report on an empty directory.
        let produced = (try? FileManager.default.contentsOfDirectory(atPath: destDir.path)) ?? []
        guard !produced.isEmpty else {
            throw InstallError.extractionFailed
        }
    }

    /// Grants the owner write access across a freshly extracted tree.
    ///
    /// `unzip` and `unrar` restore the permission bits **stored in the archive**.
    /// Some mods ship directories as `r-xr-xr-x`, and since removing a directory's
    /// contents requires write access *on that directory*, the app ended up
    /// unable to delete a folder it had just written itself: updating such a mod
    /// failed with "you don't have permission to access it", with no way out from
    /// the UI.
    ///
    /// Read-only bits carry no meaning for a mod folder we own and manage, so we
    /// normalise them at extraction time rather than working around them later.
    static func grantOwnerWriteAccess(in directory: URL) {
        let fm = FileManager.default
        var targets = [directory]
        if let e = fm.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let url as URL in e { targets.append(url) }
        }
        for url in targets {
            guard let mode = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber else {
                continue
            }
            var isDirectory: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDirectory)
            // Directories also need `x` to be traversable while we delete them.
            let wanted = mode.uint16Value | (isDirectory.boolValue ? 0o700 : 0o600)
            guard wanted != mode.uint16Value else { continue }
            try? fm.setAttributes([.posixPermissions: NSNumber(value: wanted)], ofItemAtPath: url.path)
        }
    }

    /// Deletes an item, repairing permissions first if the filesystem refuses.
    ///
    /// Folders installed before `grantOwnerWriteAccess` existed are still on
    /// disk as read-only, so a plain `removeItem` keeps failing for them. Rather
    /// than asking the user to run `chmod`, retry once with write access granted.
    static func removeItemGrantingWriteAccess(atPath path: String) throws {
        let fm = FileManager.default
        do {
            try fm.removeItem(atPath: path)
        } catch {
            grantOwnerWriteAccess(in: URL(fileURLWithPath: path))
            try fm.removeItem(atPath: path)
        }
    }

    /// Whether an extraction tool's exit status means "the files are there".
    ///
    /// Info-ZIP (`unzip`), `unrar` and `7z` all share the same convention:
    /// `0` = clean, `1` = **succeeded with warnings**, `>= 2` = real error.
    /// Status 1 is not an edge case here: every archive packaged on Windows
    /// with backslashes as path separators — the majority of what Nexus
    /// serves — extracts correctly and exits 1 with
    /// `warning: … appears to use backslashes as path separators`.
    /// Treating that as a failure rejected perfectly valid mods.
    static func isTolerableExitStatus(_ status: Int32) -> Bool {
        status == 0 || status == 1
    }

    /// Minimal environment that pins the locale to `C` (POSIX) for child
    /// processes whose output we parse — notably `unzip -l`. Without this the
    /// summary line would be translated under the user's UI locale ("3
    /// fichiers" instead of "3 files") and our parser would silently fail,
    /// disabling the zip-bomb size guard. We deliberately inherit the rest of
    /// the parent environment (PATH especially) so Homebrew tools like
    /// `unrar` / `unar` / `7z` are still found at their default locations.
    private static let cLocaleEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["LANG"] = "C"
        env["LC_ALL"] = "C"
        return env
    }()

    /// Searches the standard PATH locations (plus Homebrew paths) for a RAR
    /// extraction tool, in order of preference: `unrar` (official, fastest),
    /// `unar` (The Unarchiver, handles many formats), `7z` (7-Zip).
    /// Returns `nil` if none is available.
    /// Répertoires où chercher un outil d'extraction.
    ///
    /// La liste est explicite plutôt que déduite du `PATH` : une application
    /// lancée depuis le Finder n'hérite pas du `PATH` du shell — launchd lui
    /// donne `/usr/bin:/bin:/usr/sbin:/sbin` — donc se fier au `PATH` seul
    /// ferait échouer l'extraction chez quelqu'un qui a pourtant l'outil. Le
    /// `PATH` est tout de même ajouté, pour couvrir un lancement en terminal et
    /// les emplacements exotiques.
    static var toolSearchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var dirs = [
            "/opt/homebrew/bin",                       // Homebrew (Apple Silicon)
            "/usr/local/bin",                          // Homebrew (Intel), installations manuelles
            "/opt/local/bin",                          // MacPorts
            "/opt/homebrew/sbin", "/usr/local/sbin",
            "/usr/bin", "/bin",
            home.appendingPathComponent(".homebrew/bin").path,
            home.appendingPathComponent("bin").path,
            home.appendingPathComponent(".nix-profile/bin").path,
            "/run/current-system/sw/bin",              // Nix
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs.append(contentsOf: path.split(separator: ":").map(String.init))
        }
        var seen = Set<String>()
        return dirs.filter { seen.insert($0).inserted }
    }

    /// Premier exécutable portant l'un des noms donnés, dans l'ordre de
    /// préférence.
    static func firstAvailableTool(named names: [String]) -> String? {
        for name in names {
            for dir in toolSearchPaths {
                let p = "\(dir)/\(name)"
                if FileManager.default.isExecutableFile(atPath: p) { return p }
            }
        }
        return nil
    }

    /// Outil capable de lire un `.7z`. `7zz` est le nom moderne du binaire
    /// 7-Zip sur Homebrew — l'omettre ferait échouer l'extraction sur une
    /// machine qui a pourtant l'outil. `unrar` est absent de la liste : il ne
    /// lit pas le 7z.
    static func find7zTool() -> (path: String, arguments: (String, String) -> [String])? {
        // Toute la famille 7-Zip partage la même ligne de commande. `7zz` est le
        // binaire de la formule `sevenzip` ; `7z`/`7za` viennent de p7zip ;
        // `7zr` est la version réduite, limitée au format .7z — précisément le
        // nôtre. `unrar` est absent : il ne lit pas le 7z.
        if let path = firstAvailableTool(named: ["7zz", "7z", "7za", "7zr"]) {
            return (path, { archive, dest in ["x", "-aoa", "-o\(dest)", archive] })
        }
        if let path = firstAvailableTool(named: ["unar"]) {
            return (path, { archive, dest in ["-f", "-o", dest, archive] })
        }
        return nil
    }

    static func findRarTool() -> (path: String, arguments: (String, String) -> [String])? {
        // `unrar x -o+ <archive> <dest>/` — officiel, le plus rapide.
        if let path = firstAvailableTool(named: ["unrar"]) {
            return (path, { archive, dest in ["x", "-o+", archive, dest + "/"] })
        }
        // `unar -f -o <dest> <archive>`
        if let path = firstAvailableTool(named: ["unar"]) {
            return (path, { archive, dest in ["-f", "-o", dest, archive] })
        }
        // La famille 7-Zip lit aussi le RAR. `7zr` en est écarté : il ne gère
        // que le format .7z.
        if let path = firstAvailableTool(named: ["7zz", "7z", "7za"]) {
            return (path, { archive, dest in ["x", "-aoa", "-o\(dest)", archive] })
        }
        return nil
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

        // Archives can carry read-only directory modes; normalise them now so
        // the installed copy stays manageable (see `grantOwnerWriteAccess`).
        Self.grantOwnerWriteAccess(in: tempDir)

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

    /// Installs selected mods from a temporary directory to the game's Mods/
    /// folder. New mods and updates of previously-disabled mods land as
    /// `Mods/.X` (disabled by default — SMAPI ignores dotted folders); an
    /// update of an enabled mod lands at `Mods/X` to keep it enabled. Applies
    /// conflict resolutions (overwrite+backup, rename, skip) and config-file
    /// resolutions (keep existing / use new) per selection.
    ///
    /// `detectedMods` is the original list from `ZipModInfo` so selections can
    /// be resolved to actual mod metadata + source paths. The `modsDisabledPath`
    /// parameter is retained for source compatibility but is no longer used —
    /// disabled mods now live inside Mods/ as `.X`.
    func install(from tempDir: URL, to modsDisabledPath: String, selections: [InstallSelection], detectedMods: [DetectedMod], gameDir: String, existingMods: [ModItem]) throws {
        guard !gameDir.isEmpty else { throw InstallError.gameDirEmpty }
        let backupManager = ModInstallBackupManager.shared

        // Ensure Mods/ exists as the single install destination.
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        try fm.createDirectory(atPath: modsPath, withIntermediateDirectories: true, attributes: nil)

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
            // already exists as an enabled or disabled mod under Mods/).
            let existingMod = findExistingMod(detectedMod.uniqueId, in: existingMods)

            let finalDestFolderName: String
            // User config files (config.json/fr.json) snapshotted from the
            // existing mod folder *before* it is removed, then restored on
            // top of the freshly installed copy. Drag-drop install must never
            // silently overwrite a user's live config.
            var preservedConfigs: [String: URL] = [:]
            // Guarantee temp snapshot files never leak, even if this loop
            // iteration throws partway through (after snapshotting configs but
            // before restoring them). On the success path the entries are
            // removed one-by-one as they're restored, leaving the cleanup a
            // no-op; on the failure path any leftover snapshots are swept.
            defer {
                for (_, tmp) in preservedConfigs {
                    try? fm.removeItem(at: tmp)
                }
            }
            if let existing = existingMod, let resolution = selection.conflictResolution {
                switch resolution {
                case .skip:
                    continue
                case .overwriteWithBackup:
                    // A pack/group child carries a nested folderName like
                    // "PackName/ChildMod" (see ModItem.folderName /
                    // scanFolderForMods), while the freshly detected mod's
                    // folderName is only the last path component (e.g.
                    // "ChildMod"). Installing to the last component would
                    // detach the child from its pack folder and create a
                    // stray top-level entry — the existing location must be
                    // preserved so the replacement lands exactly where the
                    // old version lived.
                    finalDestFolderName = existing.folderName
                    // The backup MUST succeed before the original is ever
                    // touched — swallowing a failure here (e.g. disk full)
                    // would delete the only copy of the existing mod with no
                    // backup anywhere to recover it from. A `.modNotFound`,
                    // however, signals a corrupted/leftover state where the
                    // existing folder is already gone on disk: there is
                    // nothing to back up, so we tolerate it and let the
                    // install proceed (the new copy replaces nothing).
                    do {
                        _ = try backupManager.createBackup(for: existing, gameDir: gameDir, reason: .beforeUpdate)
                    } catch ModInstallBackupManager.InstallBackupError.modNotFound {
                        // Existing mod's folder is missing on disk (corruption
                        // from a prior partial install) — nothing to back up.
                    } catch {
                        throw InstallError.backupFailed(error.localizedDescription)
                    }
                    // Remove the existing folder wherever it lives (enabled
                    // as Mods/X, or disabled as Mods/.X) so the new copy is
                    // the only one. `physicalFolderName` carries the dot
                    // prefix for a disabled mod.
                    let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
                    let existingFolder = (modsPath as NSString).appendingPathComponent(existing.physicalFolderName)
                    if fm.fileExists(atPath: existingFolder) {
                        preservedConfigs = snapshotUserConfigs(from: existingFolder)
                        try Self.removeItemGrantingWriteAccess(atPath: existingFolder)
                    }
                case .rename:
                    finalDestFolderName = "\(detectedMod.folderName)_\(timestampStamp)"
                case .keepExisting, .useNew:
                    finalDestFolderName = detectedMod.folderName
                }
            } else {
                finalDestFolderName = detectedMod.folderName
            }

            // If the existing mod was enabled, install to Mods/X to keep it
            // enabled. New mods and previously-disabled mods go to Mods/.X
            // (disabled by default — the user toggles them on explicitly).
            let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
            let destBasePath: String
            let destFolderPrefix: String
            if let existing = existingMod, existing.isEnabled, selection.conflictResolution == .overwriteWithBackup {
                destBasePath = modsPath
                destFolderPrefix = ""   // enabled
            } else {
                destBasePath = modsPath
                destFolderPrefix = "."  // disabled
            }

            try fm.createDirectory(atPath: destBasePath, withIntermediateDirectories: true, attributes: nil)

            let destPath = (destBasePath as NSString).appendingPathComponent(destFolderPrefix + finalDestFolderName)

            // Replace destination folder with the new mod copy. For a
            // pack/group child, `finalDestFolderName` is a nested path
            // (e.g. "PackName/ChildMod") whose intermediate parent may not
            // exist yet — create it first, mirroring ModInstallBackupManager
            // and ModConfigBackupManager.
            let destParent = (destPath as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: destParent, withIntermediateDirectories: true, attributes: nil)
            if fm.fileExists(atPath: destPath) {
                try fm.removeItem(atPath: destPath)
            }
            try fm.copyItem(atPath: sourcePath.path, toPath: destPath)

            // Touch the installed folder's mtime to NOW. `copyItem` preserves
            // the source folder's mtime (which reflects when the modder
            // packaged the archive, not when it was installed on this machine).
            // The update checker compares the Nexus upload date against this
            // folder mtime for same-version updates; without this touch every
            // re-install would leave a stale date and the mod would be
            // re-flagged as needing an update on the next check.
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: destPath)

            // Restore preserved user configs/translations on top of the freshly
            // installed mod (config.json + all language files the user had).
            // The existing folder was deleted above, so without this restore the
            // user would lose their settings/translations if the new archive
            // doesn't ship them (common case). Failures must surface, not be
            // swallowed — a silent failure here means data loss.
            for (configFile, tmp) in preservedConfigs {
                let cfg = (destPath as NSString).appendingPathComponent(configFile)
                if fm.fileExists(atPath: cfg) {
                    try? fm.removeItem(atPath: cfg)
                }
                do {
                    try fm.copyItem(atPath: tmp.path, toPath: cfg)
                    // Mark as consumed so the defer cleanup skips it.
                    preservedConfigs.removeValue(forKey: configFile)
                } catch {
                    // Don't mask the error — the caller should know config
                    // restore failed (the backup in ModInstallBackupManager
                    // still has the original files for manual recovery). The
                    // leftover temp snapshot is cleaned by the defer above.
                    throw InstallError.installFailed("Failed to restore \(configFile): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Copies `config.json` and all SMAPI language files from `modFolder` into
    /// temp files so they survive the folder being replaced during an overwrite
    /// install. See `ModConfigFiles.preservable` for the full file list.
    private func snapshotUserConfigs(from modFolder: String) -> [String: URL] {
        var snapshots: [String: URL] = [:]
        for configFile in ModConfigFiles.preservable {
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
    case installFailed(String)
    case rarToolMissing

    var errorDescription: String? {
        switch self {
        case .extractionFailed: return "Failed to extract archive file"
        case .unsafeContent: return "This archive contains unsafe content (symbolic links) and was rejected."
        case .gameDirEmpty: return "Game directory is not set."
        case .backupFailed(let reason): return "Backup of the existing mod failed, installation aborted: \(reason)"
        case .installFailed(let reason): return "Installation failed: \(reason)"
        case .rarToolMissing: return "RAR extraction requires 'unrar', 'unar', or '7z' (install via Homebrew: brew install unrar)."
        }
    }
}