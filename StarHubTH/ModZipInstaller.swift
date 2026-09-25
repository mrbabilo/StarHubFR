import Foundation

/// Zip validation, analysis, extraction and installation for mods, via
/// `/usr/bin/unzip` (plain `swiftc` build, no SPM dependencies).
class ModZipInstaller {
    /// Magasin de sauvegardes d'installation, **injecté** : sinon les tests
    /// écrivaient dans le vrai `Application Support` (1 148 entrées de
    /// fixture mesurées le 2026-08-21).
    private let backupManager: ModInstallBackupManager

    init(backupManager: ModInstallBackupManager = .shared) {
        self.backupManager = backupManager
    }

    private let fm = FileManager.default
    private let maxZipSize: Int64 = 500 * 1024 * 1024 // 500MB

    /// Mod installé portant cet identifiant, composants de packs compris
    /// (`Array<ModItem>.mod(withUniqueId:)`, seule copie testée ; les vues
    /// manquaient 296 déclarations).
    private func findExistingMod(_ uniqueId: String, in mods: [ModItem]) -> ModItem? {
        mods.mod(withUniqueId: uniqueId)
    }

    /// Détection de conflit, **pure** (`LogicalFolderNameCollisionTests`).
    /// Occupant de l'identifiant = `.folderExists` (une mise à jour garde son
    /// dossier) ; sinon seulement, occupant du **nom logique**, forcément un
    /// autre UniqueID (deux `[CP] Sounds of the Valley` au parc, identifiant
    /// changé entre 3.1.0 et 4.0.0) : sans ce signal, pause silencieuse et
    /// identité partagée.
    /// - Returns: le mod installé par identifiant et zéro ou un conflit.
    static func detectConflicts(forFolderName folderName: String,
                                manifest: ModManifest,
                                in existingMods: [ModItem]) -> (existing: ModItem?, conflicts: [ModConflict]) {
        if let existing = existingMods.mod(withUniqueId: manifest.uniqueId) {
            let conflict = ModConflict(
                conflictType: .folderExists,
                folderName: folderName,
                existingName: existing.name,
                existingVersion: existing.version,
                newVersion: manifest.version,
                resolutionOptions: [.overwriteWithBackup, .rename, .skip]
            )
            return (existing, [conflict])
        }
        if let occupant = existingMods.mod(withLogicalFolderName: folderName) {
            let conflict = ModConflict(
                conflictType: .nameTakenByOtherMod,
                folderName: folderName,
                existingName: occupant.name,
                existingVersion: occupant.version,
                newVersion: manifest.version,
                resolutionOptions: [.overwriteWithBackup, .rename, .skip]
            )
            return (nil, [conflict])
        }
        return (nil, [])
    }

    /// Chemins comptés **après installation** (ancre, réconciliation,
    /// id→dossier). Abstention seulement quand une **copie du même
    /// `UniqueID` reste en place** (conflit d'identifiant renommé,
    /// `existingVersion`) : affirmer la copie décrirait mal l'active. Un nom
    /// pris par un **autre** mod compte comme avant. Déplacement physique
    /// (X63, `displacedFrom`) exclu aussi.
    static func accountingPaths(written: [InstalledModPath],
                                selections: [InstallSelection],
                                detectedMods: [DetectedMod]) -> [String] {
        let sameUniqueIdCopyRemains = Set(selections
            .filter { selection in
                guard selection.conflictResolution == .rename else { return false }
                return detectedMods.first { $0.id == selection.modId }?
                    .existingVersion != nil
            }
            .map(\.modId))
        return written
            .filter { !sameUniqueIdCopyRemains.contains($0.modId) && $0.displacedFrom == nil }
            .map(\.path)
    }
    // Uncompressed cap, checked via `unzip -l` before extraction:
    // `maxZipSize` only bounds the compressed file (zip bombs ~1000:1).
    private let maxExtractedSize: Int64 = 2 * 1024 * 1024 * 1024 // 2GB
    // Plafond de composants par archive : les vrais packs dépassent 10
    // (« Hidden Pelican Village » 13, « MultiverseArchive Full » 15,
    // 2026-09-01). Pas une garde de sécurité (taille, zip-slip, symlinks le
    // sont) : 50 écarte l'absurde.
    private let maxModsPerZip = 50

    /// Format déduit de la signature, seule source fiable : l'URL gratuite de
    /// Nexus n'a pas toujours d'extension (un `.7z` enregistré « .zip »).
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

    /// Total non compressé d'un `7zz l -slt` : somme des lignes `Size =` nues
    /// (`Physical/Headers/Packed Size` ignorées). `nil` si rien lu (vide,
    /// chiffré) : l'appelant fail-open, comme pour `unzip -l`.
    static func totalSizeFromSevenZipListing(_ output: String) -> Int64? {
        var total: Int64 = 0
        var found = false
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            // `.whitespacesAndNewlines` : un `\r` final (CRLF) casserait le `Int64`.
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("Size =") else { continue }
            let value = line.dropFirst("Size =".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let n = Int64(value) {
                total += n
                found = true
            }
        }
        return found ? total : nil
    }

    /// Noms d'entries d'un `7zz l -slt` (`Path = …`), pour la garde
    /// zip-slip (audit 2026-08-05).
    static func pathNamesFromSevenZipListing(_ output: String) -> [String] {
        // ⚠️ Le listing s'ouvre sur un **en-tête de l'archive** dont le `Path =`
        // est son chemin absolu : compté, il rejetait tout `.7z`/`.rar` (Nexus
        // 47840). Entries après la ligne de tirets. Sans en-tête (tests, format
        // futur) : tout est lu, gardé plutôt qu'ignoré.
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let firstEntry = lines.firstIndex { $0.hasPrefix("----------") }
            .map { lines.index(after: $0) } ?? lines.startIndex
        return lines[firstEntry...].compactMap { line in
            guard line.hasPrefix("Path =") else { return nil }
            return String(line.dropFirst("Path =".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// True if an entry name escapes via `..` or an absolute path (zip-slip).
    /// Pure, tested.
    static func containsTraversalPath(_ names: [String]) -> Bool {
        names.contains { name in
            name.hasPrefix("/") || name.split(separator: "/").contains("..")
        }
    }

    /// Strips the archive extension for a clean folder name.
    static func strippingArchiveExtension(from name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return name }
        return (name as NSString).deletingPathExtension
    }

    /// Formats acceptés ; sans `.7z`, une extension inconnue passait pour
    /// « archive corrompue ».
    static let supportedExtensions: Set<String> = ["zip", "rar", "7z"]

    /// Sépare un dépôt multiple : archives ouvrables (signature, extension en
    /// repli) dans l'ordre, et le reste, écarté sans bloquer le lot.
    static func partitionDroppedFiles(_ urls: [URL]) -> (archives: [URL], rejected: [URL]) {
        var archives: [URL] = []
        var rejected: [URL] = []
        for url in urls {
            let declared = url.pathExtension.lowercased()
            if detectedArchiveExtension(at: url) != nil || supportedExtensions.contains(declared) {
                archives.append(url)
            } else {
                rejected.append(url)
            }
        }
        return (archives, rejected)
    }

    // MARK: - Validation
    /// Validates size, format and structure (`.zip`, `.rar`, `.7z`).
    func validateZip(at url: URL) -> ValidationStatus {
        // Format lu dans la signature, pas l'extension (fichiers mal nommés
        // courants). L'extension distingue seulement « non géré » de « illisible ».
        let declared = url.pathExtension.lowercased()

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
        let bytes = [UInt8](handle.readData(ofLength: 8))
        handle.closeFile()

        // Signature reconnue = valide ; `extractArchive` relit la même
        // `archiveExtension(forSignature:)`, les deux ne divergent pas.
        if Self.archiveExtension(forSignature: bytes) != nil {
            return .valid
        }

        // Sans signature : extension gérée → corrompu ; sinon format non géré.
        if Self.supportedExtensions.contains(declared) {
            return .corrupted
        }
        return .unsupportedFormat(declared)
    }

    /// Total uncompressed size from `unzip -l`'s summary, no extraction.
    /// `nil` if unparsable: callers fail open.
    private func uncompressedSize(ofZipAt url: URL) -> Int64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-l", url.path]
        // C locale: a French UI ("N fichiers") would return nil and silently
        // disable the zip-bomb guard.
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

    /// Même rôle pour 7z et rar via `find7zTool` ; sans outil, l'extraction
    /// échouerait aussi. Total via `totalSizeFromSevenZipListing`.
    private func uncompressedSizeViaSevenZip(at url: URL) -> Int64? {
        guard let tool = Self.find7zTool() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.path)
        process.arguments = ["l", "-slt", url.path]
        process.environment = Self.cLocaleEnvironment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return nil }
        return Self.totalSizeFromSevenZipListing(output)
    }

    /// Zip-slip pré-validé (`unzip` extrait les `../` ; 7zz/unrar les
    /// assainissent, gardé par défense en profondeur). Fail-open si le listing
    /// échoue. Audit 2026-08-05.
    static func hasTraversalEntry(zipUrl: URL, ext: String) -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.environment = Self.cLocaleEnvironment
        if ext == "zip" {
            // `-Z1` (mode ZipInfo) liste les noms d'entries, un par ligne.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-Z1", zipUrl.path]
        } else {
            // 7z et rar lus par l'outil 7z (cf. commentaire uncompressedSizeViaSevenZip).
            guard let tool = Self.find7zTool() else { return false }
            process.executableURL = URL(fileURLWithPath: tool.path)
            process.arguments = ["l", "-slt", zipUrl.path]
        }
        guard (try? process.run()) != nil else { return false }
        // **Lire avant d'attendre** : tube de 64 Ko ; 3 000 entrées = 411 Ko,
        // l'app figée sur « Analyse de l'archive… » (2026-08-27). Les voisines
        // avaient le bon ordre.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return false
        }
        let names = ext == "zip"
            ? output.split(separator: "\n").map(String.init)
            : Self.pathNamesFromSevenZipListing(output)
        return Self.containsTraversalPath(names)
    }

    // MARK: - Analysis

    /// Analyzes a zip. The temp dir goes to `onTempDir` so `install()`
    /// reuses the single extraction.
    func analyzeZip(at url: URL, gameDir: String, existingMods: [ModItem], onTempDir: ((URL) -> Void)? = nil) throws -> ZipModInfo {
        let status = validateZip(at: url)
        guard case .valid = status else {
            return ZipModInfo(zipName: url.lastPathComponent, detectedMods: [], validationStatus: status, conflicts: [], estimatedSize: 0)
        }

        // Uncompressed size checked before extracting (zip bomb). 7z/rar via
        // `uncompressedSizeViaSevenZip`.
        let format = Self.detectedArchiveExtension(at: url)
        let uncompressed = format == "zip"
            ? uncompressedSize(ofZipAt: url)
            : uncompressedSizeViaSevenZip(at: url)
        if uncompressed ?? 0 > maxExtractedSize {
            return ZipModInfo(zipName: url.lastPathComponent, detectedMods: [], validationStatus: .oversized, conflicts: [], estimatedSize: 0)
        }

        let tempDir = try extractToTemp(zipUrl: url)
        // NOTE: no defer cleanup — the caller owns the temp dir (`cleanupTempDir`).
        onTempDir?(tempDir)

        return analyzeExtractedDir(at: tempDir, zipName: url.lastPathComponent, existingMods: existingMods)
    }

    /// Analyzes an extracted dir (structure + `ZipModInfo`); split out so
    /// tests lay out mod folders without a real archive.
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

    /// Résumé du contenu réel : « manifest.json manquant » n'apprend rien, la
    /// cause (archives imbriquées, fichiers à copier, doc) se voit d'un coup
    /// d'œil.
    static func topLevelSummary(of dir: URL) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return entries.filter { !$0.hasPrefix(".") }.sorted().prefix(12).map { name in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path,
                                           isDirectory: &isDir)
            return isDir.boolValue ? "\(name)/" : name
        }
    }

    /// Builds `ZipModInfo` from the temp dir; nil if no mod is found.
    private func buildInfo(from tempDir: URL, structure: ZipStructure, zipName: String, existingMods: [ModItem], fallbackStatus: ValidationStatus) -> ZipModInfo? {
        var detectedMods: [DetectedMod] = []
        var conflicts: [ModConflict] = []
        var totalSize: Int64 = 0

        func scanFolder(at path: URL, relativePath: String, folderName: String) {
            guard let enumerator = fm.enumerator(at: path, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
                return
            }

            var currentModManifest: ModManifest?
            // Shallower manifest wins (enumerator order is unspecified): a bundled
            // sub-library must not override the real one.
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
                        // `ManifestJSON` gère le JSON5 (commentaires `//`, virgule traînante du
                        // modèle SMAPI) : sinon « manifest.json manquant ».
                        if let json = ManifestJSON.decode(rawString),
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

            let detection = Self.detectConflicts(forFolderName: folderName,
                                                 manifest: manifest,
                                                 in: existingMods)
            conflicts.append(contentsOf: detection.conflicts)

            let detectedMod = DetectedMod(
                folderName: folderName,
                relativePath: relativePath,
                manifest: manifest,
                hasConfigFiles: hasConfigFiles,
                dependencies: dependencies,
                dependencyDetails: manifest.dependencies,
                existingVersion: detection.existing
            )
            detectedMods.append(detectedMod)
            totalSize += modSize
        }

        switch structure {
        case .singleMod(let baseFolder):
            let modPath = tempDir.appendingPathComponent(baseFolder)
            scanFolder(at: modPath, relativePath: baseFolder, folderName: baseFolder)
        case .multiMod(let folders):
            // Components under one shared top-level folder (a genuine pack, e.g.
            // "Lilybrook/[CC]") keep it: Mods/<Parent>/<leaf>, shown as one entry.
            // Flat collections stay one folder per component.
            let sharedParent = Self.commonParent(of: folders)
            for folder in folders {
                let modPath = tempDir.appendingPathComponent(folder)
                let leaf = (folder as NSString).lastPathComponent
                let destFolderName = sharedParent.map { "\($0)/\(leaf)" } ?? leaf
                scanFolder(at: modPath, relativePath: folder, folderName: destFolderName)
            }
        case .flatRoot:
            // No enclosing folder: the temp dir's name becomes the mod folder.
            // Extension retirée quelle qu'elle soit (sinon « MonMod.7z »).
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

    /// Single shared top-level parent ("Lilybrook"), or nil (root entries,
    /// flat collection, mix).
    private static func commonParent(of folders: [String]) -> String? {
        let parents = folders.map { ($0 as NSString).deletingLastPathComponent }
        guard parents.allSatisfy({ !$0.isEmpty }) else { return nil }
        let unique = Set(parents)
        return unique.count == 1 ? unique.first : nil
    }

    /// Detects the structure of extracted zip contents.
    private func detectZipStructure(at tempDir: URL) -> ZipStructure {
        var rootHasManifest = false
        /// Dossiers contenant un `manifest.json`, chemin relatif complet (ex.
        /// `Parchment/Parchment`) pour distinguer l'imbrication.
        var manifestFolders: [String] = []

        // `subpathsOfDirectory`: relative paths directly, avoiding the
        // `/var` vs `/private/var` mismatch.
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
                    // Chemin relatif complet jusqu'au dossier du manifest.
                    let parentPath = components.dropLast().joined(separator: "/")
                    if !manifestFolders.contains(parentPath) {
                        manifestFolders.append(parentPath)
                    }
                }
            }
        }

        // A manifest nested under another is a bundled dependency: dropped
        // (order-independent ancestor check).
        manifestFolders = manifestFolders.filter { folder in
            !manifestFolders.contains { other in
                other != folder && folder.hasPrefix(other + "/")
            }
        }

        // 1 : un dossier à la racine → singleMod. 2 : plusieurs sous un même
        // dossier racine → multiMod. 3 : plusieurs à la racine → multiMod.
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

    /// Extracts an archive. ZIP: `/usr/bin/unzip`. RAR/7z: first of `unrar`,
    /// `unar`, `7z` (runtime check); `rarToolMissing` if none.
    @discardableResult
    static func extractArchive(zipUrl: URL, to destDir: URL) throws -> [String] {
        // Format par signature (comme `validateZip`) ; extension en repli.
        let ext = Self.detectedArchiveExtension(at: zipUrl) ?? zipUrl.pathExtension.lowercased()

        // Garde zip-slip avant d'extraire (audit 2026-08-05).
        if Self.hasTraversalEntry(zipUrl: zipUrl, ext: ext) {
            throw InstallError.extractionFailed(
                "archive rejetée : une entrée sort du dossier de destination")
        }

        var notes: [String] = []

        if ext == "zip" {
            let unzip = Self.runExtractor(tool: "/usr/bin/unzip",
                                          arguments: ["-q", "-o", zipUrl.path, "-d", destDir.path])
            if !Self.isTolerableExitStatus(unzip.status) {
                // `unzip` refuse les noms non UTF-8 (vieux zips DOS) : `Illegal byte
                // sequence`, statut 2, extraction partielle. « Kalash's More Fruit
                // Trees » (41318) : 315/320 contre 320 avec `7zz`/`unar`. Repli sur les
                // outils du `.rar`/`.7z`.
                notes.append(Self.diagnostic(tool: "/usr/bin/unzip", result: unzip))
                guard let fallback = Self.find7zTool() else {
                    // Sans repli, nommer l'outil manquant (seule trace).
                    notes.append("aucun outil de repli installé (7zz, 7z, 7za ou unar)"
                                 + " — `brew install sevenzip` ou `brew install unar`")
                    throw InstallError.extractionFailed(notes.joined(separator: "\n"))
                }

                // Dossier vide avant la seconde passe.
                try? FileManager.default.removeItem(at: destDir)
                try FileManager.default.createDirectory(at: destDir,
                                                        withIntermediateDirectories: true)

                let retry = Self.runExtractor(tool: fallback.path,
                                              arguments: fallback.arguments(zipUrl.path,
                                                                            destDir.path))
                guard Self.isTolerableExitStatus(retry.status) else {
                    notes.append(Self.diagnostic(tool: fallback.path, result: retry))
                    throw InstallError.extractionFailed(notes.joined(separator: "\n"))
                }
                let name = (fallback.path as NSString).lastPathComponent
                notes.append("extraction reprise avec \(name) : réussie")
            }
        } else {
            // Outil externe ; `unrar` ne lit pas le 7z, deux listes.
            guard let tool = ext == "rar" ? Self.findRarTool() : Self.find7zTool() else {
                throw InstallError.rarToolMissing
            }
            let result = Self.runExtractor(tool: tool.path,
                                           arguments: tool.arguments(zipUrl.path, destDir.path))
            guard Self.isTolerableExitStatus(result.status) else {
                throw InstallError.extractionFailed(Self.diagnostic(tool: tool.path,
                                                                    result: result))
            }
        }

        // Status 1 accepted, so disk content is the proof: warnings + nothing =
        // "extraction failed", not "no valid mod structure".
        let produced = (try? FileManager.default.contentsOfDirectory(atPath: destDir.path)) ?? []
        guard !produced.isEmpty else {
            throw InstallError.extractionFailed("l'archive n'a produit aucun fichier")
        }
        return notes
    }

    /// Lance un extracteur et rend son verdict. stderr dans le même tube, **lu
    /// avant l'attente** (sinon interblocage, voir `hasTraversalEntry`).
    private static func runExtractor(tool: String, arguments: [String])
        -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        // Locale C : diagnostics en anglais, comparables d'un rapport à l'autre.
        process.environment = Self.cLocaleEnvironment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        return (process.terminationStatus,
                output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Ligne de journal : outil, statut, sortie tronquée à six lignes.
    private static func diagnostic(tool: String,
                                   result: (status: Int32, output: String)) -> String {
        let name = (tool as NSString).lastPathComponent
        let lines = result.output.split(separator: "\n", omittingEmptySubsequences: true)
        let shown = lines.prefix(6).joined(separator: " / ")
        let suffix = lines.count > 6 ? " (+\(lines.count - 6) lignes)" : ""
        return "\(name) a rendu le statut \(result.status)"
            + (shown.isEmpty ? "" : " : \(shown)\(suffix)")
    }

    /// Grants owner write access across an extracted tree: archives restore
    /// `r-xr-xr-x` dirs, and the app then couldn't delete what it wrote.
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

    /// Deletes, retrying once with write access (older read-only installs).
    static func removeItemGrantingWriteAccess(atPath path: String) throws {
        let fm = FileManager.default
        do {
            try fm.removeItem(atPath: path)
        } catch {
            grantOwnerWriteAccess(in: URL(fileURLWithPath: path))
            try fm.removeItem(atPath: path)
        }
    }

    /// Met à la corbeille, droits ouverts si nécessaire : `trashItem` échoue
    /// en 0555 (Code=513, 2026-09-04). Rend l'URL dans la corbeille.
    @discardableResult
    static func trashItemGrantingWriteAccess(atPath path: String) throws -> URL? {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        var resulting: NSURL?
        do {
            try fm.trashItem(at: url, resultingItemURL: &resulting)
        } catch {
            grantOwnerWriteAccess(in: url)
            try fm.trashItem(at: url, resultingItemURL: &resulting)
        }
        return resulting as URL?
    }

    /// Exit status meaning "files are there": `0` clean, `1` warnings (every
    /// Windows-packaged archive with backslashes), `>= 2` error.
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
    /// L'héritage est la moitié qui compte : `SmapiInstaller` en avait une
    /// copie qui ne la tenait pas, et son installateur mourait faute de
    /// `PATH`. Une seule source désormais (`ChildProcessEnvironment`, Core).
    private static let cLocaleEnvironment: [String: String] =
        ChildProcessEnvironment.localeLocked(to: "C")

    /// Répertoires où chercher un outil d'extraction : liste explicite, car
    /// une app lancée du Finder n'hérite pas du `PATH` du shell ; le `PATH`
    /// est ajouté pour le terminal et les emplacements exotiques.
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

    /// Premier exécutable des noms donnés, par ordre de préférence.
    static func firstAvailableTool(named names: [String]) -> String? {
        for name in names {
            for dir in toolSearchPaths {
                let p = "\(dir)/\(name)"
                if FileManager.default.isExecutableFile(atPath: p) { return p }
            }
        }
        return nil
    }

    /// Outil lisant le `.7z` (`7zz` = nom Homebrew moderne ; pas `unrar`).
    static func find7zTool() -> (path: String, arguments: (String, String) -> [String])? {
        // Même ligne de commande pour la famille 7-Zip : `7zz` (sevenzip),
        // `7z`/`7za` (p7zip), `7zr` (réduit au .7z).
        if let path = firstAvailableTool(named: ["7zz", "7z", "7za", "7zr"]) {
            return (path, { archive, dest in ["x", "-aoa", "-o\(dest)", archive] })
        }
        if let path = firstAvailableTool(named: ["unar"]) {
            return (path, { archive, dest in ["-f", "-o", dest, archive] })
        }
        return nil
    }

    /// RAR tool by preference: `unrar`, `unar`, 7-Zip; `nil` if none.
    static func findRarTool() -> (path: String, arguments: (String, String) -> [String])? {
        // `unrar x -o+ <archive> <dest>/` — officiel, le plus rapide.
        if let path = firstAvailableTool(named: ["unrar"]) {
            return (path, { archive, dest in ["x", "-o+", archive, dest + "/"] })
        }
        // `unar -f -o <dest> <archive>`
        if let path = firstAvailableTool(named: ["unar"]) {
            return (path, { archive, dest in ["-f", "-o", dest, archive] })
        }
        // 7-Zip lit aussi le RAR, sauf `7zr`.
        if let path = firstAvailableTool(named: ["7zz", "7z", "7za"]) {
            return (path, { archive, dest in ["x", "-aoa", "-o\(dest)", archive] })
        }
        return nil
    }

    /// Ce que la dernière extraction a dit (repli, avertissements), lu par le
    /// ViewModel qui journalise.
    private(set) var lastExtractionNotes: [String] = []

    /// Extracts an archive to a fresh temp directory.
    func extractToTemp(zipUrl: URL) throws -> URL {
        lastExtractionNotes = []
        let timestamp = String(Int(Date().timeIntervalSince1970))
        // UUID suffix: two analyses in the same second must not share a temp dir.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarHubTH_\(timestamp)_\(UUID().uuidString)")

        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

        do {
            // Gardé pour le journal : sinon un repli reste silencieux.
            lastExtractionNotes = try Self.extractArchive(zipUrl: zipUrl, to: tempDir)
        } catch {
            try? fm.removeItem(at: tempDir)
            throw error
        }

        // Normalise read-only modes (see `grantOwnerWriteAccess`).
        Self.grantOwnerWriteAccess(in: tempDir)

        // Drop macOS metadata (not a mod, not copied; matters for flatRoot).
        stripMacOSXJunk(from: tempDir)

        // Reject symlinks: a crafted link can point outside the temp dir.
        do {
            try guardAgainstSymlinks(in: tempDir)
        } catch {
            try? fm.removeItem(at: tempDir)
            throw error
        }

        return tempDir
    }

    /// Removes `__MACOSX` folders left by `unzip`.
    private func stripMacOSXJunk(from dir: URL) {
        let macosx = dir.appendingPathComponent("__MACOSX")
        if fm.fileExists(atPath: macosx.path) {
            try? fm.removeItem(at: macosx)
        }
    }

    /// Fails closed on any symlink (mods never need one).
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

    /// Installs selected mods into Mods/. New mods and updates of disabled ones
    /// land as `Mods/.X`; an update of an enabled mod stays `Mods/X`. Applies
    /// conflict and config-file resolutions. `modsDisabledPath` is unused
    /// (kept for source compatibility).
    /// - Returns: chemins **réellement écrits**, dans l'ordre des sélections —
    ///   seule source honnête (un composant reste dans son pack, état
    ///   d'activation, horodatage `.rename`). Recalculés par la feuille, ils
    ///   manquaient les composants de pack (239/1 095) et la mise à jour
    ///   restait annoncée. Chaque chemin porte l'`id` de sa sélection (voir
    ///   `InstalledModPath`).
    @discardableResult
    func install(from tempDir: URL, to modsDisabledPath: String, selections: [InstallSelection], detectedMods: [DetectedMod], gameDir: String, existingMods: [ModItem]) throws -> [InstalledModPath] {
        guard !gameDir.isEmpty else { throw InstallError.gameDirEmpty }
        var installedPaths: [InstalledModPath] = []
        // Sauvegarde produite ? Sinon rien à élaguer.
        var didBackUp = false

        // Ensure Mods/ exists as the single install destination.
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        try fm.createDirectory(atPath: modsPath, withIntermediateDirectories: true, attributes: nil)

        let timestampStamp = Self.stampedFolderSuffix()

        for selection in selections {
            guard selection.selected else { continue }

            guard let detectedMod = detectedMods.first(where: { $0.id == selection.modId }) else {
                continue
            }

            // Source: "" for flatRoot, else the subfolder name.
            let sourcePath: URL
            if detectedMod.relativePath.isEmpty {
                sourcePath = tempDir
            } else {
                sourcePath = tempDir.appendingPathComponent(detectedMod.relativePath)
            }
            guard fm.fileExists(atPath: sourcePath.path) else { continue }

            // Conflict only if the same UniqueID already exists under Mods/.
            let existingMod = findExistingMod(detectedMod.uniqueId, in: existingMods)

            // Nom **logique** pris par un autre UniqueID (`.nameTakenByOtherMod`),
            // sans occupant d'identifiant : `.skip` n'installe rien ;
            // `.overwriteWithBackup` fait de l'occupant l'« existing » (sauvegarde,
            // purge, delta, configs, état actif) ; `.rename` pose un nom horodaté
            // **logique** (`nonCollidingDestination` en filet). Exclusif avec le
            // conflit d'identifiant.
            var effectiveExisting = existingMod
            // Renommer le NOM LOGIQUE, pas le chemin : un occupant ACTIF laisse
            // `Mods/.[CP] X` libre et le nouveau prenait son identité, en silence.
            var renamesForNameTaken = false
            if existingMod == nil,
               let occupant = existingMods.mod(withLogicalFolderName: detectedMod.folderName) {
                if selection.conflictResolution == .skip {
                    continue
                }
                if selection.conflictResolution == .overwriteWithBackup {
                    effectiveExisting = occupant
                }
                if selection.conflictResolution == .rename {
                    renamesForNameTaken = true
                }
            }

            let finalDestFolderName: String
            // config.json/fr.json snapshotted before removal and restored after:
            // drag-drop must never overwrite live config.
            var preservedConfigs: [String: URL] = [:]
            // A1-T7 — données écrites en jouant, hors de la liste blanche des 18 noms.
            var preservedExtras: [String: URL] = [:]
            var extrasRestored = 0
            var extrasRestoredPaths: [String] = []
            var extrasFailed: [String] = []
            var extrasSkipped = 0
            // C2-T4 — delta de clés, branche overwrite seulement.
            var pendingKeyDelta: ModUpdateKeyDelta? = nil
            // Temp snapshots never leak, even if the iteration throws.
            defer {
                for (_, tmp) in preservedConfigs {
                    try? fm.removeItem(at: tmp)
                }
                for (_, tmp) in preservedExtras {
                    try? fm.removeItem(at: tmp)
                }
            }
            if let existing = effectiveExisting, let resolution = selection.conflictResolution {
                switch resolution {
                case .skip:
                    continue
                case .overwriteWithBackup:
                    // A pack child's folderName is nested ("PackName/ChildMod"): keep the
                    // existing location, else the child detaches from its pack.
                    finalDestFolderName = existing.folderName
                    // The backup MUST succeed before touching the original (disk full would
                    // lose the only copy). `.modNotFound` = folder already gone: tolerated.
                    do {
                        _ = try backupManager.createBackup(for: existing, gameDir: gameDir, reason: .beforeUpdate)
                        // Même version réinstallée = sauvegarde redondante, purgée pour ce mod
                        // (85 sauvegardes, 172 Mo au parc). Jamais la purge globale.
                        backupManager.purgeRedundantBackups(limitedTo: existing.folderName)
                        didBackUp = true
                    } catch ModInstallBackupManager.InstallBackupError.modNotFound {
                        // Existing folder missing on disk: nothing to back up.
                    } catch {
                        throw InstallError.backupFailed(error.localizedDescription)
                    }
                    // Remove the existing folder, enabled or disabled (`physicalFolderName`).
                    let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
                    let existingFolder = (modsPath as NSString).appendingPathComponent(existing.physicalFolderName)
                    if fm.fileExists(atPath: existingFolder) {
                        // C2-T4 §5 — ancien état lu ici ou jamais ; le neuf au tempDir (le
                        // config.json restauré masquerait l'embarqué).
                        let oldSnapshot = UpdateKeySnapshot.read(folder: URL(fileURLWithPath: existingFolder))
                        let newSnapshot = UpdateKeySnapshot.read(folder: sourcePath)
                        pendingKeyDelta = ModUpdateKeyDelta.compare(
                            old: oldSnapshot, new: newSnapshot,
                            uniqueId: detectedMod.uniqueId, folderName: existing.folderName)
                        preservedConfigs = snapshotUserConfigs(from: existingFolder)
                        // A1-T7 — ce que l'archive ne livre pas, le mod l'a écrit ; lu ici ou
                        // jamais. La liste blanche (et `i18n/en.json`) relève de
                        // `snapshotUserConfigs` (C2-T4).
                        let existingURL = URL(fileURLWithPath: existingFolder)
                        let extras = PreservedModData.extraPaths(
                            installed: PreservedModData.relativeFiles(under: existingURL, using: fm),
                            shippedByArchive: PreservedModData.relativeFiles(under: sourcePath, using: fm),
                            alreadyHandled: ModConfigFiles.preservableFiles(under: existingFolder)
                                .map(\.relativePath))
                        preservedExtras = PreservedModData.snapshot(extras, from: existingURL, using: fm)
                        try Self.removeItemGrantingWriteAccess(atPath: existingFolder)
                    }
                case .rename:
                    finalDestFolderName = "\(detectedMod.folderName)_\(timestampStamp)"
                }
            } else if renamesForNameTaken {
                // Nom pris, `.rename` : horodaté dans le nom **logique** (deux mods
                // visibles, `displacedFrom == nil`).
                finalDestFolderName = "\(detectedMod.folderName)_\(timestampStamp)"
            } else {
                finalDestFolderName = detectedMod.folderName
            }

            // Existing enabled → Mods/X; new or previously disabled → Mods/.X.
            let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
            let destBasePath: String
            let destFolderPrefix: String
            if let existing = effectiveExisting, existing.isEnabled, selection.conflictResolution == .overwriteWithBackup {
                destBasePath = modsPath
                destFolderPrefix = ""   // enabled
            } else {
                destBasePath = modsPath
                destFolderPrefix = "."  // disabled
            }

            try fm.createDirectory(atPath: destBasePath, withIntermediateDirectories: true, attributes: nil)

            // X63 — la destination peut appartenir à **un autre mod** (reconnu par
            // `UniqueID` seulement) : l'occupant disparaissait sans sauvegarde ni mot.
            // Cas réel (deux `[CP] Seaside Sounds`, X60).
            let intendedPath = (destBasePath as NSString)
                .appendingPathComponent(destFolderPrefix + finalDestFolderName)
            let destPath = nonCollidingDestination(
                basePath: destBasePath,
                prefix: destFolderPrefix,
                folderName: finalDestFolderName,
                uniqueId: detectedMod.uniqueId,
                stamp: timestampStamp
            )
            let displacedFrom = destPath == intendedPath ? nil : finalDestFolderName

            // Create the nested pack parent if missing before copying.
            let destParent = (destPath as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: destParent, withIntermediateDirectories: true, attributes: nil)
            // Rollback copy of the destination kept in tempDir (not Mods/, the
            // scanner would see it): a failed copy restores it (audit 2026-08-05).
            var rollbackBackup: String? = nil
            if fm.fileExists(atPath: destPath) {
                let bk = tempDir.appendingPathComponent(".rollback_\(UUID().uuidString)").path
                try fm.moveItem(atPath: destPath, toPath: bk)
                rollbackBackup = bk
            }
            do {
                try fm.copyItem(atPath: sourcePath.path, toPath: destPath)
                // Succès : le backup n'est plus nécessaire.
                if let bk = rollbackBackup {
                    try? Self.removeItemGrantingWriteAccess(atPath: bk)
                }
            } catch {
                if let bk = rollbackBackup {
                    // Effacer la copie partielle puis restaurer l'original.
                    try? Self.removeItemGrantingWriteAccess(atPath: destPath)
                    try? fm.moveItem(atPath: bk, toPath: destPath)
                }
                throw error
            }

            // Touch mtime to NOW (`copyItem` keeps the archive's date): the checker
            // compares it to Nexus upload dates, else every reinstall is re-flagged.
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: destPath)

            // Restore preserved configs/translations; failures surface (data loss
            // otherwise).
            try restoreUserConfigs(&preservedConfigs, into: destPath)
            // A1-T7 — extras ensuite, **sans lancer** (la sauvegarde a tout) ;
            // échecs au bilan. Réglage « ne pas remettre » : snapshots jetés, bilan
            // `skipped`.
            if PreservedModData.shouldRestore(defaults: .standard) {
                let extrasOutcome = PreservedModData.restore(
                    &preservedExtras, into: URL(fileURLWithPath: destPath), using: fm)
                extrasRestored = extrasOutcome.restored
                extrasRestoredPaths = extrasOutcome.restoredPaths
                extrasFailed = extrasOutcome.failed
            } else {
                extrasSkipped = preservedExtras.count
                preservedExtras.removeAll()
            }

            // Le mod est entièrement posé : son chemin peut être annoncé.
            installedPaths.append(InstalledModPath(modId: selection.modId, path: destPath,
                                                   displacedFrom: displacedFrom,
                                                   keyDelta: pendingKeyDelta,
                                                   extrasRestored: extrasRestored,
                                                   extrasRestoredPaths: extrasRestoredPaths,
                                                   extrasFailed: extrasFailed,
                                                   extrasSkipped: extrasSkipped))
        }

        // Rétention par âge **une fois** par installation (index entier) : ici
        // naissent les sauvegardes, ici on élague.
        if didBackUp {
            _ = backupManager.cleanupOldBackups()
        }

        return installedPaths
    }

    /// Snapshots `config.json` and all `i18n/*.json` keyed by **relative
    /// path**, so each goes back where it belongs (the root-only lookup lost
    /// translations on every update, B4-T4). See
    /// `ModConfigFiles.preservableFiles`.
    func snapshotUserConfigs(from modFolder: String) -> [String: URL] {
        var snapshots: [String: URL] = [:]
        for file in ModConfigFiles.preservableFiles(under: modFolder) {
            // C2-T4 §4 — `i18n/default.json`/`en.json` sont l'anglais de l'AUTEUR :
            // les restaurer figeait l'anglais (garde trop large de B4-T4). Filtre par
            // chemin relatif. Le backup manuel sauvegarde tout.
            if Self.isAuthorLanguageFile(file.relativePath) { continue }
            // Flat temp name; the relative path is the key.
            let flat = file.relativePath.replacingOccurrences(of: "/", with: "__")
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("starhubth_preserve_\(UUID().uuidString)_\(flat)")
            do {
                try fm.copyItem(atPath: file.url.path, toPath: tmp.path)
                snapshots[file.relativePath] = tmp
            } catch {
                try? fm.removeItem(at: tmp)
            }
        }
        return snapshots
    }

    /// Fichier de langue de l'auteur sous `i18n/`, non protégé.
    static func isAuthorLanguageFile(_ relativePath: String) -> Bool {
        let posix = relativePath.replacingOccurrences(of: "\\", with: "/")
        return posix == "i18n/default.json" || posix == "i18n/en.json"
            || posix.hasSuffix("/i18n/default.json") || posix.hasSuffix("/i18n/en.json")
    }

    /// Restores snapshots by relative path, recreating `i18n/` if needed;
    /// restored entries are removed so `defer` only sweeps leftovers.
    /// Failures surface (backups keep the originals).
    func restoreUserConfigs(_ preservedConfigs: inout [String: URL], into destPath: String) throws {
        // Iterate a copy of the keys (mutated in the loop).
        for relativePath in Array(preservedConfigs.keys) {
            guard let tmp = preservedConfigs[relativePath] else { continue }
            let cfg = (destPath as NSString).appendingPathComponent(relativePath)
            // The archive may lack i18n/: create it; a failure must surface.
            let cfgDir = (cfg as NSString).deletingLastPathComponent
            if !fm.fileExists(atPath: cfgDir) {
                try fm.createDirectory(atPath: cfgDir, withIntermediateDirectories: true)
            }
            if fm.fileExists(atPath: cfg) {
                try? fm.removeItem(atPath: cfg)
            }
            do {
                try fm.copyItem(atPath: tmp.path, toPath: cfg)
                preservedConfigs.removeValue(forKey: relativePath)
            } catch {
                throw InstallError.installFailed("Failed to restore \(relativePath): \(error.localizedDescription)")
            }
        }
    }

    /// `UniqueID` du mod à `path`, ou `nil` — qui ne veut **pas** dire
    /// « libre » (racine de pack, manifeste hors UTF-8) : traité comme
    /// occupé, jamais comme permission d'effacer.
    private func installedUniqueId(at path: String) -> String? {
        let manifestPath = (path as NSString).appendingPathComponent("manifest.json")
        guard let data = fm.contents(atPath: manifestPath),
              let raw = String(data: data, encoding: .utf8),
              let json = ManifestJSON.decode(raw),
              let uniqueId = json.caseInsensitiveValue(forKey: "UniqueID") as? String else {
            return nil
        }
        let trimmed = uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Où poser `folderName` : libre → pris ; même `UniqueID` → pris
    /// (mise à jour) ; autre chose → nom horodaté. Le nouveau bouge, jamais
    /// l'installé. Seule la **dernière** composante change (pack conservé).
    private func nonCollidingDestination(basePath: String, prefix: String, folderName: String,
                                         uniqueId: String, stamp: String) -> String {
        let candidate = (basePath as NSString).appendingPathComponent(prefix + folderName)
        guard fm.fileExists(atPath: candidate) else { return candidate }
        if let owner = installedUniqueId(at: candidate),
           owner.compare(uniqueId, options: .caseInsensitive) == .orderedSame {
            return candidate
        }

        let parentRelative = (folderName as NSString).deletingLastPathComponent
        let leaf = (folderName as NSString).lastPathComponent
        // Même horodatage pour toute l'installation ; le compteur sépare.
        for index in 0...99 {
            let suffix = index == 0 ? "_\(stamp)" : "_\(stamp)_\(index)"
            let stampedLeaf = leaf + suffix
            let relative = parentRelative.isEmpty
                ? stampedLeaf
                : (parentRelative as NSString).appendingPathComponent(stampedLeaf)
            let path = (basePath as NSString).appendingPathComponent(prefix + relative)
            if !fm.fileExists(atPath: path) { return path }
        }
        // Filet : un UUID plutôt qu'un écrasement.
        let fallbackLeaf = "\(leaf)_\(stamp)_\(UUID().uuidString)"
        let relative = parentRelative.isEmpty
            ? fallbackLeaf
            : (parentRelative as NSString).appendingPathComponent(fallbackLeaf)
        return (basePath as NSString).appendingPathComponent(prefix + relative)
    }

    /// Short timestamp suffix for renamed duplicate mod folders.
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
    case extractionFailed(String)
    case unsafeContent
    case gameDirEmpty
    case backupFailed(String)
    case installFailed(String)
    case rarToolMissing

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let detail): return "Failed to extract archive file: \(detail)"
        case .unsafeContent: return "This archive contains unsafe content (symbolic links) and was rejected."
        case .gameDirEmpty: return "Game directory is not set."
        case .backupFailed(let reason): return "Backup of the existing mod failed, installation aborted: \(reason)"
        case .installFailed(let reason): return "Installation failed: \(reason)"
        case .rarToolMissing: return "RAR extraction requires 'unrar', 'unar', or '7z' (install via Homebrew: brew install unrar)."
        }
    }

    /// B2-T4 : commande copiable, alignée sur le message et l'accueil :
    /// `unar`, un seul conseil.
    var copyableCommand: String? {
        switch self {
        case .rarToolMissing: return "brew install unar"
        default: return nil
        }
    }
}