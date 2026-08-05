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
/// Duplicate UniqueIDs across an enabled (`Mods/X`) and a disabled
/// (`Mods/.X`) mod folder are **reported only**: the correct resolution
/// depends on user intent (which copy to keep), so they are surfaced for
/// manual action rather than auto-merged.
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
        /// Path relative to the Mods/ root it was found in.
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
        /// Duplicate UniqueIDs found across an enabled (`X`) and a disabled
        /// (`.X`) mod folder inside Mods/ (not auto-resolved — surfaced for
        /// manual action).
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

    // Fichiers/dossiers junk OS et préfixe AppleDouble : source unique `OSJunk`
    // (Models/OSJunk.swift). Ce fichier gardait une copie conforme, divergente
    // dès qu'OSJunk est enrichi — la quatrième copie (cf. diverging-copies-hide-bugs).
    /// Public so the scanner can skip `_Trash_*` folders (mods quarantined by
    /// a prior repair run) without re-deriving the prefix.
    public static let trashPrefix = "_Trash_"

    private let fm: FileManager

    public init(fileManager: FileManager = .default) {
        self.fm = fileManager
    }

    // MARK: - Public entry point

    /// Scans the game's Mods/ folder (both enabled entries and `.X`
    /// disabled ones — SMAPI ignores dotted folders), quarantines corrupt/junk
    /// items, and detects duplicates. Safe to call on every scan —
    /// already-quarantined content (under any `_Trash_*` folder) is never
    /// re-scanned.
    @discardableResult
    public func repairIfNeeded(gameDir: String, detectDuplicates: Bool = true) -> Report {
        guard !gameDir.isEmpty else { return Report() }

        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")

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

        // Duplicate detection is optional: the disk-walking implementation
        // re-decodes every manifest, which is redundant when the caller has
        // already scanned. scanMods passes detectDuplicates=false here and
        // instead calls detectDuplicates(from:) with the already-parsed mods.
        // The default stays on so standalone callers and tests get a full report.
        let duplicates = detectDuplicates ? self.detectDuplicates(modsPath: modsPath) : []

        return Report(quarantined: allItems, duplicates: duplicates, trashPath: _trashPath)
    }

    // MARK: - Per-folder repair

    /// Walks the Mods/ root, collecting and quarantining junk + corrupt
    /// items. Returns the list of items moved. Disabled mod folders (`.X`)
    /// at the top level are left untouched — this is intentional: the
    /// repairer cleans filesystem corruption (orphans, OS junk, empty dirs),
    /// not the user's enabled/disabled state.
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
            let isOsJunk = OSJunk.files.contains(entry) || entry.hasPrefix(OSJunk.appleDoublePrefix)
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
                if OSJunk.folders.contains(entry) {
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
            // root of Mods/ (a common clutter case).
            if OSJunk.files.contains(entry) {
                if moveToTrash(fullPath: fullPath, modsRoot: modsRoot, gameDir: gameDir, trashProvider: trashProvider) {
                    items.append(Item(kind: .osJunkFile, relativePath: rel,
                                      reason: "OS metadata file (\(entry)), not used by Stardew/SMAPI."))
                }
                continue
            }
            if entry.hasPrefix(OSJunk.appleDoublePrefix) {
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

            if OSJunk.files.contains(filename) {
                if moveToTrash(fullPath: fullPath, modsRoot: resolvedRoot, gameDir: gameDir, trashProvider: trashProvider) {
                    items.append(Item(kind: .osJunkFile, relativePath: rel,
                                      reason: "OS metadata file (\(filename)), not used by Stardew/SMAPI."))
                }
            } else if filename.hasPrefix(OSJunk.appleDoublePrefix) {
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

    /// Detects mods that exist in BOTH an enabled folder (`Mods/X`) and a
    /// disabled folder (`Mods/.X`) under the same UniqueID. Reported, not
    /// auto-resolved.
    private func detectDuplicates(modsPath: String) -> [Duplicate] {
        let collected = collectUniqueIds(in: modsPath)

        var enabled: [(id: String, folder: String, isEnabled: Bool)] = []
        var disabled: [(id: String, folder: String, isEnabled: Bool)] = []
        for entry in collected {
            if entry.isEnabled {
                enabled.append(entry)
            } else {
                disabled.append(entry)
            }
        }

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

    /// Detects X/.X duplicate UniqueIDs straight from an already-scanned mod
    /// list (standalone mods + every pack child). O(N) in-memory — no
    /// filesystem walk, no manifest decode — because the scanner has already
    /// parsed every UniqueID and enabled state. Output-equivalent to the
    /// disk-walking `detectDuplicates(modsPath:)` above, but free after a scan;
    /// `scanMods` uses it so the launch scan doesn't decode every manifest
    /// twice (once here, once in the scanner).
    public func detectDuplicates(from mods: [ModItem]) -> [Duplicate] {
        var enabled: [(id: String, folder: String)] = []
        var disabled: [(id: String, folder: String)] = []
        for m in mods {
            let leafs: [ModItem] = m.isGroup ? (m.children ?? []) : [m]
            for c in leafs where !c.uniqueId.isEmpty {
                if c.isEnabled {
                    enabled.append((c.uniqueId, c.folderName))
                } else {
                    disabled.append((c.uniqueId, c.folderName))
                }
            }
        }
        let enabledLower = Dictionary(
            enabled.map { ($0.id.lowercased(), $0.folder) },
            uniquingKeysWith: { a, _ in a }
        )
        var duplicates: [Duplicate] = []
        for d in disabled {
            if let enabledFolder = enabledLower[d.id.lowercased()] {
                duplicates.append(Duplicate(uniqueId: d.id, enabledFolder: enabledFolder, disabledFolder: d.folder))
            }
        }
        return duplicates.sorted { $0.uniqueId < $1.uniqueId }
    }

    /// Collects `(uniqueId, topLevelFolder, isEnabled)` tuples for every
    /// manifest.json at any depth under `modsPath`. Reads manifests leniently
    /// (same comment stripping as the scanner); a manifest with no readable
    /// UniqueID is skipped. The top-level folder name keeps its dot prefix
    /// (when present) so callers can tell enabled from disabled entries.
    private func collectUniqueIds(in modsPath: String) -> [(id: String, folder: String, isEnabled: Bool)] {
        let resolvedRoot = URL(fileURLWithPath: modsPath).resolvingSymlinksInPath().path
        // Enumerate WITHOUT `.skipsHiddenFiles` so the dot-prefixed disabled
        // mod folders (`.X`) are visible. Nested OS junk (.DS_Store, ._Foo
        // inside a real mod) is filtered out explicitly below.
        guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: resolvedRoot),
                                             includingPropertiesForKeys: [.isSymbolicLinkKey],
                                             options: []) else {
            return []
        }
        var results: [(id: String, folder: String, isEnabled: Bool)] = []
        for case let fileURL as URL in enumerator {
            // Never follow symlinks into manifests outside the game dir.
            if let vals = try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
               vals.isSymbolicLink == true {
                continue
            }
            guard fileURL.lastPathComponent.lowercased() == "manifest.json" else { continue }
            // Resolve the enumerator-reported path so it shares the same
            // root form as `resolvedRoot` — macOS enumerators report
            // `/private/...` even when the root URL was `/tmp/...`, and a
            // naive prefix strip would yield a bogus relative path.
            let resolvedFile = fileURL.resolvingSymlinksInPath().path
            // Relative path via la source canonique `relativePath` (hasPrefix +
            // dropFirst), comme ligne 271. Un `replacingOccurrences(of: root)`
            // amputait tout chemin contenant la racine plusieurs fois.
            let rel = relativePath(of: resolvedFile, from: resolvedRoot)
            let firstComponent = (rel as NSString).components(separatedBy: "/").first ?? rel
            if firstComponent.hasPrefix(Self.trashPrefix) { continue }

            // The top-level folder is the first path component; its dot
            // prefix (if any) signals a disabled mod. Strip it for the
            // stored folder name so duplicates compare against the logical
            // name on both sides.
            let topFolder = (rel as NSString).components(separatedBy: "/").first ?? rel
            let isDisabled = topFolder.hasPrefix(".") && !OSJunk.files.contains(topFolder) && !topFolder.hasPrefix(OSJunk.appleDoublePrefix)
            let logicalFolder = isDisabled ? String(topFolder.dropFirst()) : topFolder

            // Skip manifests nested under a known OS junk folder at the top
            // level (e.g. `__MACOSX/...`). These would otherwise pollute the
            // duplicate-detection set with throwaway UniqueIDs.
            if OSJunk.folders.contains(topFolder) { continue }

            guard let data = try? Data(contentsOf: fileURL),
                  let raw = String(data: data, encoding: .utf8) else { continue }
            let clean = raw.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
            // Match the scanner's reading options so JSON5 manifests (trailing
            // commas, // comments) are parsed the same way here — otherwise a
            // JSON5 manifest that the scanner accepts would be silently
            // skipped by duplicate detection.
            // `.json5Allowed` lets JSON5 manifests (some Stardew mods ship
            // comments / trailing commas) parse. `.allowFragments` was previously
            // also set but is redundant here — the next line downcasts to a dict,
            // which a non-object fragment can never satisfy.
            var options: JSONSerialization.ReadingOptions = []
            if #available(macOS 12.0, *) {
                options.insert(.json5Allowed)
            }
            guard let cleanData = clean.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: cleanData, options: options) as? [String: Any],
                  let uid = json.caseInsensitiveValue(forKey: "UniqueID") as? String,
                  !uid.isEmpty else { continue }
            results.append((id: uid, folder: logicalFolder, isEnabled: !isDisabled))
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
