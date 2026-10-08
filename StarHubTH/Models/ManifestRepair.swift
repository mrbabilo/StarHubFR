import Foundation

/// A1-T2 — reprendre un `manifest.json` que même le lecteur clément refuse.
///
/// SMAPI ne charge pas un mod dont le manifeste ne décode pas : le mod
/// disparaît du jeu alors qu'il reste dans la liste avec des métadonnées
/// vides. Deux sources de réparation, dans cet ordre :
///
/// 1. **le backup d'installation** (`Backups/ModInstalls`) : chaque
///    installation et mise à jour y archivée le dossier **complet** du mod,
///    manifeste compris. Copier le seul `manifest.json` du backup le plus
///    récent répare sans toucher au contenu actuel — la corruption d'un
///    manifeste n'atteint que lui, et la version installée peut être plus
///    récente que la version sauvegardée : restaurer le dossier entier
///    ferait une marche arrière de version en écrasant des fichiers sains.
/// 2. **la réinstallation Nexus** (dernière version) quand aucun backup ne
///    porte le manifeste : c'est l'affaire du ViewModel, qui emprunte la
///    file de téléchargement commune.
///
/// Le type ne connaît ni backups manager ni Nexus : il reçoit des
/// candidats `(date, dossier d'origine, chemin du backup)` et rend des
/// chemins — testable sans disque réel autre qu'un dossier temporaire.
public enum ManifestRepair {

    /// Un backup d'installation candidat, aplati depuis
    /// `ModInstallBackup` par l'appelant — le type reste indépendant du
    /// manager et de son index.
    public struct BackupCandidate: Equatable, Sendable {
        public let timestamp: Date
        /// Le nom logique du **dossier racine** tel qu'au moment de la
        /// sauvegarde (`originalFolderName`) : un composant de pack
        /// (`Racine/Composant`) vit dans le backup de sa racine.
        public let originalFolderName: String
        /// Le dossier du backup — il contient le dossier du mod.
        public let backupPath: String

        public init(timestamp: Date, originalFolderName: String, backupPath: String) {
            self.timestamp = timestamp
            self.originalFolderName = originalFolderName
            self.backupPath = backupPath
        }
    }

    /// Erreurs nommées : chacune dit ce qu'il faut faire ensuite, pas
    /// seulement ce qui a échoué.
    public enum RestoreError: Error, Equatable {
        /// Aucun backup candidat ne porte ce manifeste — tenter Nexus.
        case noBackupManifest
        /// Le dossier du mod a disparu du disque entre le signalement et le
        /// geste — rescaner, le signal doit suivre la réalité.
        case destinationMissing(String)
        /// La copie a échoué (permissions — le piège 0555 mesure réelle du
        /// parc — ou disque). Le message d'`underlying` dit laquelle.
        case copyFailed(String)
    }

    /// Le manifeste sain du **backup le plus récent** qui le porte, ou `nil`.
    ///
    /// Un candidat compte quand sa racine est celle du mod (`Racine` pour
    /// un composant) **et** que le fichier existe : un backup d'installation
    /// archive le dossier entier, donc le manifeste vit à
    /// `<backupPath>/<folderName>/manifest.json` — le sous-chemin d'un
    /// composant compris.
    public static func backupManifest(folderName: String,
                                      candidates: [BackupCandidate],
                                      fileManager: FileManager = .default)
        -> (path: String, date: Date)? {
        let root = String(folderName.split(separator: "/")[0])
        return candidates
            .filter { $0.originalFolderName == root }
            .compactMap { candidate -> (path: String, date: Date)? in
                let base = (candidate.backupPath as NSString).appendingPathComponent(folderName)
                let path = (base as NSString).appendingPathComponent("manifest.json")
                guard fileManager.fileExists(atPath: path) else { return nil }
                return (path, candidate.timestamp)
            }
            .max(by: { $0.date < $1.date })
    }

    /// Copie le manifeste du backup le plus récent vers le dossier du mod.
    ///
    /// - `folderName` : la clé logique, celle qui a sélectionné le candidat.
    /// - `destinationFolder` : le dossier **physique** du mod sur le disque
    ///   (`Mods/.X` pour un mod en pause — le point est sur l'entrée de
    ///   tête, jamais recalculé ici).
    ///
    /// Rend le chemin écrit. Ne touche à rien d'autre qu'un fichier
    /// `manifest.json` : le contenu actuel du mod reste intact.
    public static func restore(folderName: String,
                               destinationFolder: String,
                               candidates: [BackupCandidate],
                               fileManager: FileManager = .default) throws -> String {
        guard let source = backupManifest(folderName: folderName, candidates: candidates,
                                          fileManager: fileManager) else {
            throw RestoreError.noBackupManifest
        }
        guard fileManager.fileExists(atPath: destinationFolder) else {
            throw RestoreError.destinationMissing(destinationFolder)
        }
        let destination = (destinationFolder as NSString).appendingPathComponent("manifest.json")
        do {
            if fileManager.fileExists(atPath: destination) {
                try fileManager.removeItem(atPath: destination)
            }
            try fileManager.copyItem(atPath: source.path, toPath: destination)
            return destination
        } catch {
            throw RestoreError.copyFailed(error.localizedDescription)
        }
    }
}
