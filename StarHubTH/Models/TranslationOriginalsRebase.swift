import Foundation

/// A1-T11 — après la mise à jour d'un mod qui porte une traduction posée par
/// l'app, les originaux que la traduction avait recouverts
/// (`InstalledTranslation.replacedFiles`, dans `TranslationBackups/`) sont
/// ceux de l'**ancienne** version. Désinstaller la traduction les remettrait :
/// autre chemin de résurrection d'un fichier d'auteur périmé.
///
/// Chaque original est donc remplacé par la version neuve de l'auteur quand
/// l'archive neuve livre ce chemin, et oublié quand elle ne le livre plus.
public enum TranslationOriginalsRebase {
    public struct Step: Equatable, Sendable {
        public let relative: String
        public let backupPath: String
        /// Le fichier de l'archive neuve à copier sur l'original ; `nil` :
        /// l'auteur ne livre plus ce chemin, l'original est oublié.
        public let replacement: String?
    }

    /// - Parameter newArchive: l'archive neuve, chemins relatifs à la racine
    ///   du mod (ceux du disque de l'archive extraite).
    public static func steps(for translations: [InstalledTranslation],
                             newArchive: ModFolderHasher.Listing) -> [Step] {
        var byKey: [String: String] = [:]
        for path in newArchive.hashes.keys { byKey[ModFilePath.key(path)] = path }
        var steps: [Step] = []
        for translation in translations {
            for (relative, backup) in translation.replacedFiles.sorted(by: { $0.key < $1.key }) {
                steps.append(Step(relative: relative, backupPath: backup,
                                  replacement: byKey[ModFilePath.key(relative)]))
            }
        }
        return steps
    }

    /// Copie les originaux neufs, efface les oubliés. Rend les chemins
    /// relatifs **oubliés** (à retirer du registre) et ceux qui ont échoué.
    public static func apply(_ steps: [Step], newSource: URL,
                             using fm: FileManager = .default) -> (dropped: Set<String>, failed: [String]) {
        var dropped: Set<String> = []
        var failed: [String] = []
        for step in steps {
            let backup = URL(fileURLWithPath: step.backupPath)
            do {
                if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
                if let replacement = step.replacement {
                    try fm.createDirectory(at: backup.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
                    try fm.copyItem(at: newSource.appendingPathComponent(replacement), to: backup)
                } else {
                    dropped.insert(step.relative)
                }
            } catch {
                failed.append(step.relative)
            }
        }
        return (dropped, failed.sorted())
    }

    /// Pour chaque mod mis à jour (tri appliqué) qui porte des traductions :
    /// applique les étapes, et rend par hôte les originaux oubliés — que
    /// l'appelant retire du registre sur le fil principal.
    static func afterInstall(written: [InstalledModPath], detectedMods: [DetectedMod],
                             existingMods: [ModItem], translations: InstalledTranslationRegistry,
                             tempDir: URL) -> (dropped: [String: Set<String>], failed: [String]) {
        var dropped: [String: Set<String>] = [:]
        var failed: [String] = []
        for path in written {
            guard let plan = path.triage,
                  let detected = detectedMods.first(where: { $0.id == path.modId }),
                  let host = existingMods.first(where: {
                      $0.uniqueId.caseInsensitiveCompare(detected.uniqueId) == .orderedSame
                  })?.folderName
            else { continue }
            let entries = translations.entries(forHost: host)
            guard !entries.isEmpty else { continue }
            let source = detected.relativePath.isEmpty
                ? tempDir : tempDir.appendingPathComponent(detected.relativePath)
            let outcome = apply(steps(for: entries, newArchive: plan.newArchive), newSource: source)
            if !outcome.dropped.isEmpty { dropped[host] = outcome.dropped }
            failed += outcome.failed
        }
        return (dropped, failed)
    }
}

extension InstalledTranslationRegistry {
    /// Retire des traductions de cet hôte les originaux que l'auteur ne livre
    /// plus. `true` si le registre a changé (à réécrire sur disque).
    @discardableResult
    public mutating func forgetReplacedOriginals(_ relatives: Set<String>, host: String) -> Bool {
        guard !relatives.isEmpty else { return false }
        var changed = false
        for translation in entries(forHost: host) {
            let kept = translation.replacedFiles.filter { !relatives.contains($0.key) }
            guard kept.count != translation.replacedFiles.count else { continue }
            let updated = InstalledTranslation(
                hostFolderName: translation.hostFolderName, nexusModId: translation.nexusModId,
                nexusName: translation.nexusName, version: translation.version,
                updatedAt: translation.updatedAt, installedAt: translation.installedAt,
                files: translation.files, replacedFiles: kept)
            if self.translation(forHost: host) == translation {
                record(updated)
            } else if forgetAddon(translation) != nil {
                recordAddon(updated)
            }
            changed = true
        }
        return changed
    }
}
