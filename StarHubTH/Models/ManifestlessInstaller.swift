import Foundation

/// Dépose les fichiers d'une archive sans manifeste dans le mod qu'ils visent,
/// et sait défaire ce qu'il a fait.
///
/// Ce n'est pas une installation de mod : rien n'est créé dans `Mods/`, on
/// **écrit à l'intérieur** d'un dossier existant. Trois obligations en
/// découlent, aucune facultative :
///
/// - **Sauvegarder ce qu'on recouvre.** Un mod livré avec son propre
///   `i18n/fr.json`, écrasé par une traduction communautaire, se retrouverait
///   sans français du tout si la désinstallation se contentait d'effacer.
/// - **Ouvrir les droits.** Une bonne part du parc a ses dossiers en `0555` :
///   toute écriture passe par `RecoveredFileWriter`, qui les rend ensuite tels
///   qu'il les a trouvés.
/// - **Tout ou rien.** Un dépôt à moitié fait laisse un mod dans un état que
///   personne n'a voulu : à la première erreur, ce qui a été écrit est défait.
public enum ManifestlessInstaller {
    public enum InstallError: Error, Equatable {
        /// Le dossier du mod hôte n'est pas là où on l'attendait.
        case hostMissing(String)
        /// Un fichier de l'archive a disparu entre la lecture et la copie.
        case sourceMissing(String)
        /// L'écriture a échoué ; ce qui avait été déposé a été retiré.
        case writeFailed(String)
        /// L'écriture a échoué **et** l'annulation aussi : le mod est resté
        /// dans un état intermédiaire, et les chemins concernés sont nommés.
        /// Taire ce cas serait le pire des deux — l'utilisateur croirait son
        /// mod intact.
        case rollBackIncomplete(reason: String, leftBehind: [String])
    }

    /// Ce qu'a produit un dépôt, de quoi remplir le registre.
    public struct Outcome: Equatable {
        /// Fichiers déposés, en chemins relatifs au dossier du mod.
        public let written: [String]
        /// Fichiers recouverts → où leur copie a été mise à l'abri.
        public let replaced: [String: String]

        public init(written: [String], replaced: [String: String]) {
            self.written = written
            self.replaced = replaced
        }
    }

    /// Dépose les fichiers d'un plan.
    ///
    /// - Parameters:
    ///   - plan: ce que `ManifestlessArchive` a conclu.
    ///   - extractedRoot: le dossier où l'archive a été dépliée.
    ///   - hostPath: le dossier du mod hôte, **par son nom physique** — un mod
    ///     en pause vit dans un dossier préfixé d'un point, et le parc réel en
    ///     compte 746 sur 863. Le plan, lui, ne connaît que le nom logique.
    ///   - backupRoot: où mettre à l'abri ce qu'on recouvre.
    public static func install(plan: ManifestlessArchive.Plan,
                               extractedRoot: URL,
                               hostPath: URL,
                               backupRoot: URL,
                               now: Date = Date()) throws -> Outcome {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: hostPath.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw InstallError.hostMissing(hostPath.lastPathComponent) }

        // Une sauvegarde par dépôt, datée : deux installations successives sur
        // le même mod ne doivent pas se recouvrir l'une l'autre.
        let stamp = ISO8601DateFormatter().string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        let backupDirectory = backupRoot
            .appendingPathComponent(plan.hostFolderName, isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)

        var written: [String] = []
        var replaced: [String: String] = [:]

        do {
            for entry in plan.entries {
                let source = extractedRoot.appendingPathComponent(entry.source)
                guard fm.fileExists(atPath: source.path) else {
                    throw InstallError.sourceMissing(entry.source)
                }
                let destination = hostPath.appendingPathComponent(entry.destination)

                // Recouvrir, c'est d'abord mettre de côté.
                if fm.fileExists(atPath: destination.path) {
                    let saved = backupDirectory.appendingPathComponent(entry.destination)
                    try fm.createDirectory(at: saved.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
                    // Copie et non déplacement : si la suite échoue, le mod
                    // n'aura pas perdu son fichier le temps de la bascule.
                    try fm.copyItem(at: destination, to: saved)
                    replaced[entry.destination] = saved.path
                }

                try RecoveredFileWriter.write(from: source.path, to: destination.path,
                                              modRoot: hostPath.path)
                written.append(entry.destination)
            }
        } catch {
            // Défaire : retirer ce qu'on a déposé, remettre ce qu'on a
            // recouvert. Un mod à moitié modifié est pire qu'un dépôt refusé.
            let leftBehind = rollBack(written: written, replaced: replaced, hostPath: hostPath)
            guard leftBehind.isEmpty else {
                throw InstallError.rollBackIncomplete(reason: error.localizedDescription,
                                                      leftBehind: leftBehind)
            }
            if let installError = error as? InstallError { throw installError }
            throw InstallError.writeFailed(error.localizedDescription)
        }

        return Outcome(written: written, replaced: replaced)
    }

    /// Retire une traduction ou une greffe, et **rend** ce qu'elle avait
    /// recouvert.
    ///
    /// - Returns: les chemins relatifs qu'on n'a pas pu retirer. Vide quand
    ///   tout est défait.
    @discardableResult
    public static func uninstall(_ translation: InstalledTranslation,
                                 hostPath: URL) -> [String] {
        var failures: [String] = []
        for relative in translation.files {
            let installed = hostPath.appendingPathComponent(relative)
            do {
                if let saved = translation.replacedFiles[relative],
                   FileManager.default.fileExists(atPath: saved) {
                    // Rendre plutôt qu'effacer : le fichier d'origine du mod
                    // reprend sa place.
                    try RecoveredFileWriter.write(from: saved, to: installed.path,
                                                  modRoot: hostPath.path)
                } else if FileManager.default.fileExists(atPath: installed.path) {
                    try RecoveredFileWriter.withWriteAccess(to: installed.path,
                                                            modRoot: hostPath.path) {
                        try ModZipInstaller.removeItemGrantingWriteAccess(atPath: installed.path)
                    }
                }
            } catch {
                failures.append(relative)
            }
        }
        return failures
    }

    /// Remet le mod dans l'état où le dépôt l'a trouvé.
    ///
    /// Poursuit après chaque échec — un fichier qu'on n'a pas su défaire ne
    /// doit pas empêcher de défaire les autres — mais **les rapporte** : une
    /// annulation muette laisserait croire le mod intact alors qu'il ne l'est
    /// pas.
    ///
    /// Défait **plus large que ce qui a été écrit** : l'écriture commence par
    /// retirer la destination, donc une entrée mise à l'abri puis échouée en
    /// pleine copie a déjà perdu son fichier d'origine sans jamais entrer dans
    /// `written`. S'en tenir à `written` laisserait ce fichier-là effacé et sa
    /// sauvegarde orpheline — la perte que ce filet existe pour empêcher.
    ///
    /// - Returns: les chemins relatifs restés dans un état intermédiaire.
    private static func rollBack(written: [String], replaced: [String: String],
                                 hostPath: URL) -> [String] {
        var leftBehind: [String] = []
        let deposited = Set(written)
        let toUndo = written + replaced.keys.filter { !deposited.contains($0) }.sorted()
        for relative in toUndo {
            let installed = hostPath.appendingPathComponent(relative)
            do {
                if let saved = replaced[relative] {
                    try RecoveredFileWriter.write(from: saved, to: installed.path,
                                                  modRoot: hostPath.path)
                } else {
                    try RecoveredFileWriter.withWriteAccess(to: installed.path,
                                                            modRoot: hostPath.path) {
                        try ModZipInstaller.removeItemGrantingWriteAccess(atPath: installed.path)
                    }
                }
            } catch {
                leftBehind.append(relative)
            }
        }
        return leftBehind
    }
}
