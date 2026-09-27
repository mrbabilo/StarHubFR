import Foundation

/// A1-T11 — ce qui écrit le journal après une installation, un dépôt ou un
/// nettoyage. Les échecs sont rendus, jamais levés : l'installation a déjà
/// réussi, et la mise à jour suivante retombera sur Nexus.
enum ModHistoryRecorder {
    /// Une entrée par mod posé. Ne journalise que `accountedPaths` — la règle
    /// d'abstention de `ModZipInstaller.accountingPaths` : une copie renommée
    /// à côté de l'original partage son `UniqueID` et le décrirait mal.
    ///
    /// - Returns: les `UniqueID` dont l'écriture a échoué.
    static func recordInstall(written: [InstalledModPath], accountedPaths: [String],
                              detectedMods: [DetectedMod], existingMods: [ModItem],
                              tempDir: URL, archive: URL?, historyDirectory: URL?,
                              now: Date = Date()) -> [String] {
        let accounted = Set(accountedPaths)
        let archiveSHA256 = archive.flatMap { UpdateTriageSession.sha256(of: $0) }
        var failures: [String] = []
        for path in written where accounted.contains(path.path) {
            guard let detected = detectedMods.first(where: { $0.id == path.modId }),
                  !detected.uniqueId.isEmpty else { continue }
            let source = detected.relativePath.isEmpty
                ? tempDir : tempDir.appendingPathComponent(detected.relativePath)
            let shipped = path.triage?.newArchive ?? ModFolderHasher.listing(of: source)
            let previous = existingMods.first {
                $0.uniqueId.caseInsensitiveCompare(detected.uniqueId) == .orderedSame
            }
            let entry = ModHistory.Entry(
                date: now, kind: path.triage == nil ? .install : .update,
                fromVersion: previous?.version, toVersion: detected.version,
                archiveSHA256: archiveSHA256, nexusFileId: path.triage?.sourceFileId,
                source: archive?.lastPathComponent,
                files: ModHistory.files(of: shipped), report: path.triage?.report)
            do {
                try ModHistoryFile.append(entry, uniqueId: detected.uniqueId,
                                          directory: historyDirectory, now: now)
            } catch {
                failures.append(detected.uniqueId)
            }
        }
        return failures
    }

    /// Des fichiers déposés chez un mod hôte par l'app (sac ItemBags,
    /// traduction) : une entrée « ajout », pour que la mise à jour suivante
    /// les garde (règle 2) et que la fiche du mod les montre.
    ///
    /// Les chemins relatifs sont pris sur les chemins **résolus** des deux
    /// côtés (`/var` → `/private/var` sur macOS) ; un fichier hors de l'hôte
    /// ou illisible est ignoré.
    ///
    /// - Returns: `false` si l'écriture a échoué.
    static func recordAddition(host: ModItem, hostRoot: URL, files: [URL], source: String,
                               historyDirectory: URL?, now: Date = Date()) -> Bool {
        guard !host.uniqueId.isEmpty, !files.isEmpty else { return true }
        let base = hostRoot.resolvingSymlinksInPath().standardizedFileURL.path
        var hashes: [String: String] = [:]
        var sizes: [String: Int64] = [:]
        for url in files {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            let relative = String(path.dropFirst(base.count + 1))
            do {
                hashes[relative] = try ModFolderHasher.sha256(of: url)
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                sizes[relative] = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            } catch {
                continue
            }
        }
        let entry = ModHistory.Entry(
            date: now, kind: .addition, fromVersion: nil, toVersion: host.version,
            archiveSHA256: nil, nexusFileId: nil, source: source,
            files: ModHistory.files(of: .init(hashes: hashes, sizes: sizes)), report: nil)
        do {
            try ModHistoryFile.append(entry, uniqueId: host.uniqueId, directory: historyDirectory, now: now)
            return true
        } catch {
            return false
        }
    }
}
