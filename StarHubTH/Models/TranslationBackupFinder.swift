import Foundation

/// Retrouve une traduction française qu'une mise à jour de mod a effacée.
///
/// Une mise à jour remplace le dossier du mod, et les auteurs ne redistribuent
/// pas toujours les traductions communautaires qu'on leur a envoyées : le
/// `fr.json` disparaît sans que rien ne le signale. Sur le parc de référence,
/// **16 mods** sont dans ce cas alors qu'une sauvegarde de StarHubFR en contient
/// encore un — dont `BetterInventory`, dont la traduction de 1348 octets a été
/// emportée par une mise à jour du 25 juillet.
///
/// Les deux familles de sauvegarde ne rangent pas les fichiers de la même
/// façon : une sauvegarde d'**installation** copie le mod tel quel
/// (`<mod>/i18n/fr.json`), une sauvegarde de **configuration** met les fichiers
/// préservés à plat (`<mod>/fr.json`). Chercher sous le dossier du mod couvre
/// les deux sans avoir à les distinguer — et couvrira les dispositions futures
/// sans y toucher.
public enum TranslationBackupFinder {
    /// Un `fr.json` retrouvé, et la date qui permet de dire à l'utilisateur de
    /// quand il date.
    public struct Found: Equatable, Sendable {
        public let path: URL
        public let modifiedAt: Date

        public init(path: URL, modifiedAt: Date) {
            self.path = path
            self.modifiedAt = modifiedAt
        }
    }

    /// Le `fr.json` le plus récent retrouvé pour ce mod, tous dossiers de
    /// sauvegarde confondus.
    ///
    /// Le plus récent est le seul utile : les précédents sont forcément plus
    /// anciens que lui, donc au mieux équivalents.
    ///
    /// - Parameter folderName: le `folderName` du mod, qui porte son pack pour
    ///   un composant (`Pack/Composant`) — la même forme que sur le disque.
    public static func mostRecentFrenchFile(forModFolder folderName: String,
                                            inBackupRoots roots: [URL],
                                            fileManager: FileManager = .default) -> Found? {
        var best: Found?
        for root in roots {
            for backup in subdirectories(of: root, fileManager: fileManager) {
                // Le dossier du mod **exactement**, jamais un préfixe :
                // `BetterInventory` ne doit pas ramener le fichier de
                // `BetterInventoryPlus`.
                let modDirectory = backup.appendingPathComponent(folderName)
                guard isDirectory(modDirectory, fileManager: fileManager) else { continue }
                for candidate in frenchFiles(under: modDirectory, fileManager: fileManager) {
                    let date = modificationDate(of: candidate, fileManager: fileManager)
                    if best == nil || date > best!.modifiedAt {
                        best = Found(path: candidate, modifiedAt: date)
                    }
                }
            }
        }
        return best
    }

    // MARK: - Détail

    /// Les `fr.json` sous un dossier de mod, à sa racine comme dans son `i18n/`.
    private static func frenchFiles(under directory: URL,
                                    fileManager: FileManager) -> [URL] {
        var found: [URL] = []
        let direct = directory.appendingPathComponent("fr.json")
        if fileManager.fileExists(atPath: direct.path) { found.append(direct) }
        for child in subdirectories(of: directory, fileManager: fileManager) {
            let nested = child.appendingPathComponent("fr.json")
            if fileManager.fileExists(atPath: nested.path) { found.append(nested) }
        }
        return found
    }

    private static func subdirectories(of directory: URL,
                                       fileManager: FileManager) -> [URL] {
        // `try?` délibéré : un dossier de sauvegarde absent ou illisible n'a
        // rien à offrir, et le signaler n'aiderait personne — l'utilisateur
        // verrait simplement qu'aucune traduction n'a été retrouvée.
        let entries = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries.filter { isDirectory($0, fileManager: fileManager) }
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    private static func modificationDate(of url: URL, fileManager: FileManager) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }
}
