import Foundation

/// Detects and repairs mod folder corruption: OS junk files, empty folders
/// left by failed/partial extractions, orphan folders without any manifest,
/// and nested `Mods/Mods/` wrappers from bad extractions.
///
/// Safe items (OS junk, empty folders, manifest-less orphans, nested Mods
/// wrappers) are **moved** — never deleted — into a timestamped `_Trash_`
/// folder inside the game directory, preserving their relative structure so
/// nothing is ever lost and everything is restorable by hand.
///
/// Duplicate UniqueIDs across Mods/ and Mods_disabled/ are **reported only**:
/// the correct resolution depends on user intent (which copy to keep), so
/// they are surfaced for manual action rather than auto-merged.
///
/// This is a standalone value type: `repairIfNeeded()` performs all disk
/// mutations and returns a structured report the caller surfaces to the user.
public struct ModFolderRepairer {

    // MARK: - Report types

    public struct Item: Equatable {
        public enum Kind: String, Equatable {
            case osJunkFile
            case osJunkFolder
            case appleDouble
            case emptyFolder
            case orphanFolder
            case nestedMods
        }
        public let kind: Kind
        /// Path relative to the Mods/ (or Mods_disabled/) root it was found in.
        public let relativePath: String
        /// Why this was flagged — user-facing explanation.
        public let reason: String

        public init(kind: Kind, relativePath: String, reason: String) {
            self.kind = kind
            self.relativePath = relativePath
            self.reason = reason
        }
    }

    public struct Duplicate: Equatable {
        public let uniqueId: String
        public let enabledFolder: String
        public let disabledFolder: String

        public init(uniqueId: String, enabledFolder: String, disabledFolder: String) {
            self.uniqueId = uniqueId
            self.enabledFolder = enabledFolder
            self.disabledFolder = disabledFolder
        }
    }

    public struct Report: Equatable {
        /// Items moved to quarantine during this repair run.
        public let quarantined: [Item]
        /// Duplicate UniqueIDs found across Mods/ and Mods_disabled/ (not
        /// auto-resolved — surfaced for manual action).
        public let duplicates: [Duplicate]
        /// Absolute path of the _Trash_ folder created this run, if any.
        public let trashPath: String?

        public var isEmpty: Bool { quarantined.isEmpty && duplicates.isEmpty }

        public init(quarantined: [Item] = [], duplicates: [Duplicate] = [], trashPath: String? = nil) {
            self.quarantined = quarantined
            self.duplicates = duplicates
            self.trashPath = trashPath
        }
    }

    // MARK: - Constants (mirrors the reference Python cleaner)

    /// OS metadata files that Stardew/SMAPI never uses and that commonly sneak
    /// in via zips downloaded from Nexus.
    private static let osJunkFiles: Set<String> = [
        ".DS_Store",
        "Thumbs.db",
        "ehthumbs.db",
        "Icon\r",
    ]
    /// OS metadata directories to remove wholesale.
    private static let osJunkFolders: Set<String> = [
        "__MACOSX",
        ".Spotlight-V100",
        ".Trashes",
    ]
    /// macOS AppleDouble resource-fork files: `._<filename>`.
    private static let appleDoublePrefix = "._"
    private static let trashPrefix = "_Trash_"

    private let fm: FileManager

    public init(fileManager: FileManager = .default) {
        self.fm = fileManager
    }

    // MARK: - Public entry point

    /// Scans both mod folders, quarantines corrupt/junk items, and detects
    /// duplicates. Safe to call on every scan — already-quarantined content
    /// (under any `_Trash_*` folder) is never re-scanned.
    @discardableResult
    public func repairIfNeeded(gameDir: String) -> Report {
        guard !gameDir.isEmpty else { return Report() }

        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let disabledPath = (gameDir as NSString).appendingPathComponent("Mods_disabled")

        var allItems: [Item] = []

        // Lazily create a single trash folder for this entire repair run so
        // all quarantined items land together and can be restored as a batch.
        var _trashPath: String?
        func trashDir(for gameDir: String) -> String {
            if let existing = _trashPath { return existing }
            let p = (gameDir as NSString).appendingPathComponent("\(Self.trashPrefix)\(Self.nowStamp())")
            try? fm.createDirectory(atPath: p, withIntermediateDirectories: true)
            _trashPath = p
            return p
        }

        allItems += repairFolder(at: modsPath, gameDir: gameDir, trashProvider: trashDir)
        allItems += repairFolder(at: disabledPath, gameDir: gameDir, trashProvider: trashDir)

        let duplicates = detectDuplicates(modsPath: modsPath, disabledPath: disabledPath)

        return Report(quarantined: allItems, duplicates: duplicates, trashPath: _trashPath)
    }

    // MARK: - Per-folder repair

    /// Walks a single mod root (Mods/ or Mods_disabled/), collecting and
    /// quarantining junk + corrupt items. Returns the list of items moved.
    ///
    /// Only unambiguous junk (OS metadata, empty dirs) is auto-quarantined.
    /// Orphan folders (no manifest) and nested Mods wrappers are detected
    /// and returned in the report for manual review, but NOT auto-moved —
    /// moving legitimate user asset folders without confirmation risks data
    /// disruption.
    private func repairFolder(at modsRoot: String, gameDir: String, trashProvider: (String) -> String) -> [Item] {
        guard fm.fileExists(atPath: modsRoot) else { return [] }

        var items: [Item] = []

        // Deep sweep FIRST: OS junk files/AppleDouble nested inside valid mod
        // folders. Doing this before the top-level pass avoids enumerating
        // paths that the top-level pass moves to trash mid-scan.
        items += sweepJunkInsideMods(modsRoot: modsRoot, gameDir: gameDir, trashProvider: trashProvider)

        guard let topEntries = try? fm.contentsOfDirectory(atPath: modsRoot) else { return items }

        for entry in topEntries {
            // Skip hidden top-level entries UNLESS they are known OS junk
            // (.DS_Store, ._*, etc.) which we actively quarantine.
            let isOsJunk = Self.osJunkFiles.contains(entry) || entry.hasPrefix(Self.appleDoublePrefix)
            if entry.hasPrefix(".") && !isOsJunk { continue }

            let fullPath = (modsRoot as NSString).appendingPathComponent(entry)
            let rel = relativePath(of: fullPath, from: modsRoot)

            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)

            // --- Directory cases ---
            if isDir.boolValue {
                // Never follow symlinks at the top level — a symlinked
                // directory could point outside the game dir and auto-
                // quarantine would move foreign content.
                if let vals = try? URL(fileURLWithPath: fullPath).resourceValues(forKeys: [.isSymbolicLinkKey]),
                   vals.isSymbolicLink == true {
                    continue
                }

                // OS junk folder (e.g. __MACOSX) → quarantine wholesale.
                if Self.osJunkFolders.contains(entry) {
                    if moveToTrash(fullPath: fullPath, modsRoot: modsRoot, gameDir: gameDir, trashProvider: trashProvider) {
                        items.append(Item(kind: .osJunkFolder, relativePath: rel,
                                          reason: "OS metadata folder (\(entry)), not used by Stardew/SMAPI."))
                    }
                    continue
                }

                // Empty top-level folder → quarantine (orphan from a partial
                // extraction or a removed mod).
                if isEmptyDirectory(at: fullPath) {
                    if moveToTrash(fullPath: fullPath, modsRoot: modsRoot, gameDir: gameDir, trashProvider: trashProvider) {
                        items.append(Item(kind: .emptyFolder, relativePath: rel,
                                          reason: "Empty folder, likely a leftover from a failed extraction."))
                    }
                    continue
                }

                // The following categories (nestedMods wrapper, orphan folder
                // with no manifest) are ambiguous — a legitimate user-staged
                // asset folder or a mod that bundles a reference Mods/ dir
                // would match these heuristics. They are NOT auto-quarantined
                // to avoid moving real user data without confirmation; the
                // scan simply ignores them (no manifest → invisible to the
                // mod list) and the user can review them manually.
                continue
            }

            // --- File cases at the mod root ---
            // OS junk files anywhere in the tree are swept in a second pass
            // below; here we only handle loose files sitting directly at the
            // root of Mods/ or Mods_disabled/ (a common clutter case).
            if Self.osJunkFiles.contains(entry) {
                if moveToTrash(fullPath: fullPath, modsRoot: modsRoot, gameDir: gameDir, trashProvider: trashProvider) {
                    items.append(Item(kind: .osJunkFile, relativePath: rel,
                                      reason: "OS metadata file (\(entry)), not used by Stardew/SMAPI."))
                }
                continue
            }
            if entry.hasPrefix(Self.appleDoublePrefix) {
                if moveToTrash(fullPath: fullPath, modsRoot: modsRoot, gameDir: gameDir, trashProvider: trashProvider) {
                    items.append(Item(kind: .appleDouble, relativePath: rel,
                                      reason: "macOS AppleDouble resource-fork file, not used by Stardew/SMAPI."))
                }
                continue
            }
        }

        return items
    }

    // MARK: - Deep junk sweep inside valid mods

    /// Walks the full tree under `modsRoot` and quarantines OS junk files
    /// (.DS_Store, ._*, Thumbs.db, …) found *inside* mod folders. Only
    /// operates on files — never directories — and skips anything under an
    /// existing `_Trash_*` folder. **Symlinks are never followed** to prevent
    /// a malicious or accidental link from sweeping files outside the game
    /// directory into quarantine.
    private func sweepJunkInsideMods(modsRoot: String, gameDir: String, trashProvider: (String) -> String) -> [Item] {
        let rootURL = URL(fileURLWithPath: modsRoot)
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [] // do NOT skip hidden files — .DS_Store is itself hidden
        ) else { return [] }
        var items: [Item] = []
        for case let fileURL as URL in enumerator {
            // Skip symlinks entirely — they could point outside the game dir,
            // and quarantining through them would move foreign files into _Trash_.
            if let vals = try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
               vals.isSymbolicLink == true {
                continue
            }

            // Compute the relative path by stripping the enumerator root from
            // the file URL. We resolve both to handle the /var → /private/var
            // symlink case on macOS, where the enumerator reports resolved
            // paths even though the root URL was unresolved.
            let resolvedFile = fileURL.resolvingSymlinksInPath().path
            let resolvedRoot = rootURL.resolvingSymlinksInPath().path
            let rel = self.relativePath(of: resolvedFile, from: resolvedRoot)
            // Skip our own trash folders entirely.
            let firstComponent = (rel as NSString).components(separatedBy: "/").first ?? rel
            if firstComponent.hasPrefix(Self.trashPrefix) { continue }

            let filename = fileURL.lastPathComponent
            // fullPath is built from the resolved root so it matches what the
            // enumerator reported; moveToTrash receives the resolved root too.
            let fullPath = (resolvedRoot as NSString).appendingPathComponent(rel)

            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            if isDir.boolValue { continue }

            if Self.osJunkFiles.contains(filename) {
                if moveToTrash(fullPath: fullPath, modsRoot: resolvedRoot, gameDir: gameDir, trashProvider: trashProvider) {
                    items.append(Item(kind: .osJunkFile, relativePath: rel,
                                      reason: "OS metadata file (\(filename)), not used by Stardew/SMAPI."))
                }
            } else if filename.hasPrefix(Self.appleDoublePrefix) {
                if moveToTrash(fullPath: fullPath, modsRoot: resolvedRoot, gameDir: gameDir, trashProvider: trashProvider) {
                    items.append(Item(kind: .appleDouble, relativePath: rel,
                                      reason: "macOS AppleDouble resource-fork file, not used by Stardew/SMAPI."))
                }
            }
        }
        return items
    }

    // MARK: - Detection helpers

    /// True if `path` is a directory and contains no entries.
    private func isEmptyDirectory(at path: String) -> Bool {
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return false }
        return entries.isEmpty
    }

    // MARK: - Duplicate detection

    /// Detects mods that exist in BOTH Mods/ (enabled) and Mods_disabled/
    /// (disabled) under the same UniqueID. Reported, not auto-resolved.
    private func detectDuplicates(modsPath: String, disabledPath: String) -> [Duplicate] {
        let enabled = collectUniqueIds(in: modsPath)
        let disabled = collectUniqueIds(in: disabledPath)

        let enabledLower = Dictionary(
            enabled.map { ($0.id.lowercased(), $0) },
            uniquingKeysWith: { a, _ in a }
        )
        var duplicates: [Duplicate] = []
        for d in disabled {
            if let match = enabledLower[d.id.lowercased()] {
                duplicates.append(Duplicate(
                    uniqueId: d.id,
                    enabledFolder: match.folder,
                    disabledFolder: d.folder
                ))
            }
        }
        return duplicates.sorted { $0.uniqueId < $1.uniqueId }
    }

    /// Collects (uniqueId, topLevelFolder) pairs for every manifest.json at
    /// any depth under `modsPath`. Reads manifests leniently (same comment
    /// stripping as the scanner); a manifest with no readable UniqueID is
    /// skipped.
    private func collectUniqueIds(in modsPath: String) -> [(id: String, folder: String)] {
        let resolvedRoot = URL(fileURLWithPath: modsPath).resolvingSymlinksInPath().path
        guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: resolvedRoot),
                                             includingPropertiesForKeys: [.isSymbolicLinkKey],
                                             options: [.skipsHiddenFiles]) else {
            return []
        }
        var results: [(id: String, folder: String)] = []
        for case let fileURL as URL in enumerator {
            // Never follow symlinks into manifests outside the game dir.
            if let vals = try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
               vals.isSymbolicLink == true {
                continue
            }
            guard fileURL.lastPathComponent.lowercased() == "manifest.json" else { continue }
            // Skip manifests under a trash folder.
            let rel = fileURL.path.replacingOccurrences(of: resolvedRoot, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let firstComponent = (rel as NSString).components(separatedBy: "/").first ?? rel
            if firstComponent.hasPrefix(Self.trashPrefix) { continue }

            let topFolder = (rel as NSString).components(separatedBy: "/").first ?? rel

            guard let data = try? Data(contentsOf: fileURL),
                  let raw = String(data: data, encoding: .utf8) else { continue }
            let clean = raw.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
            // Match the scanner's reading options so JSON5 manifests (trailing
            // commas, // comments) are parsed the same way here — otherwise a
            // JSON5 manifest that the scanner accepts would be silently
            // skipped by duplicate detection.
            var options: JSONSerialization.ReadingOptions = [.allowFragments]
            if #available(macOS 12.0, *) {
                options.insert(.json5Allowed)
            }
            guard let cleanData = clean.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: cleanData, options: options) as? [String: Any],
                  let uid = json.caseInsensitiveValue(forKey: "UniqueID") as? String,
                  !uid.isEmpty else { continue }
            results.append((id: uid, folder: topFolder))
        }
        return results
    }

    // MARK: - Quarantine (move to trash)

    /// Moves `fullPath` into the timestamped trash folder, preserving its
    /// relative structure so it can be located/restored by hand. Returns true
    /// on success. On failure (permissions, locked file) the item is left in
    /// place and false is returned — never risk data loss.
    @discardableResult
    private func moveToTrash(fullPath: String, modsRoot: String, gameDir: String, trashProvider: (String) -> String) -> Bool {
        let trashDir = trashProvider(gameDir)
        let rel = relativePath(of: fullPath, from: modsRoot)
        let dest = (trashDir as NSString).appendingPathComponent(rel)

        // Ensure the parent structure exists inside trash.
        let destParent = (dest as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: destParent, withIntermediateDirectories: true)

        // Collision avoidance: append a timestamp if an entry of the same name
        // already sits in the trash (e.g. a re-run).
        let safeDest = fm.fileExists(atPath: dest) ? "\(dest)_\(Self.nowStamp())" : dest

        do {
            try fm.moveItem(atPath: fullPath, toPath: safeDest)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Path helpers

    private func relativePath(of fullPath: String, from root: String) -> String {
        let rootStd = root.hasSuffix("/") ? root : root + "/"
        if fullPath.hasPrefix(rootStd) {
            return String(fullPath.dropFirst(rootStd.count))
        }
        return (fullPath as NSString).lastPathComponent
    }

    private static func nowStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
