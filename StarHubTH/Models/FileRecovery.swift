import Foundation

/// Pourquoi un fichier de sauvegarde vaut d'être proposé à la récupération.
enum RecoveryReason: Equatable {
    /// Le fichier n'existe plus dans le mod installé. Le seul signal
    /// parfaitement sûr.
    case absentFromInstall
    /// Le fichier est là, mais la sauvegarde porte des clés qu'il n'a plus.
    case keysLostSinceBackup([String])
}

/// Un fichier qu'une sauvegarde peut rendre au mod installé.
struct RecoverableFile: Identifiable, Equatable {
    var id: String { "\(folderName)/\(relativePath)" }
    /// Le dossier d'origine du mod — la clé, comme partout ailleurs pour les
    /// sauvegardes : le même `UniqueID` peut être installé dans deux dossiers.
    let folderName: String
    /// Le nom lisible du mod, tel que la sauvegarde l'a enregistré.
    let modName: String
    /// Le chemin du fichier dans le dossier du mod — `i18n/fr.json`.
    let relativePath: String
    /// Le fichier dans la sauvegarde, à lire pour l'aperçu et à copier.
    let backupPath: String
    /// Le fichier dans le mod installé, à écrire.
    let installedPath: String
    let reason: RecoveryReason
}

/// Ce qui distingue une **perte** d'une simple divergence.
///
/// C'est la règle qui décide d'écrire dans le dossier d'un mod : un faux
/// positif écrase des réglages voulus, ce qui est plus grave que l'oubli. Un
/// `config.json` différent de sa sauvegarde est le cas *normal* — l'utilisateur
/// a réglé le mod depuis la sauvegarde. Deux signaux seulement sont sûrs :
///
/// 1. le fichier a **disparu** du mod installé ;
/// 2. la sauvegarde porte des **clés** que l'installé n'a plus.
///
/// « Revenu aux valeurs par défaut » n'en fait pas partie : ce n'est pas
/// observable. SMAPI régénère les valeurs par défaut depuis le code du mod, pas
/// depuis un fichier de référence — rien ne permet de distinguer un réglage
/// remis à sa valeur d'origine d'un réglage jamais touché.
enum FileRecoveryRules {
    /// - Parameters:
    ///   - installedKeys: les clés du fichier installé, `nil` s'il n'existe pas.
    ///   - backupKeys: les clés du fichier dans la sauvegarde.
    /// - Returns: `nil` quand il n'y a rien à proposer.
    static func reason(installedKeys: [String]?, backupKeys: [String]) -> RecoveryReason? {
        // Une sauvegarde vide n'apprend rien : ne rien proposer plutôt que de
        // proposer d'écraser par du vide.
        guard !backupKeys.isEmpty else { return nil }
        guard let installedKeys else { return .absentFromInstall }
        let present = Set(installedKeys)
        let lost = backupKeys.filter { !present.contains($0) }
        return lost.isEmpty ? nil : .keysLostSinceBackup(lost)
    }
}

/// Croise les sauvegardes d'installation avec le parc pour trouver ce qu'une
/// mise à jour a emporté.
///
/// Une mise à jour de mod écrase le dossier entier : elle emporte ce que
/// l'auteur ne redistribue pas — la traduction communautaire installée à la
/// main, les réglages. Mesuré sur le parc de référence le 2026-08-24 : **10
/// `i18n/fr.json`** ne vivent plus que dans une sauvegarde.
///
/// Les entrées/sorties sont injectées, ce qui rend le balayage vérifiable sans
/// disque.
enum RecoverableFileScanner {
    /// Les fichiers qu'un mod peut avoir perdus et qu'une sauvegarde ramène.
    /// `config.json` d'abord : c'est le seul dont une clé perdue se lit comme
    /// un réglage disparu.
    static let defaultCandidates = ["config.json", "i18n/fr.json", "i18n/fr-FR.json"]

    /// - Parameters:
    ///   - backups: toutes les sauvegardes d'installation connues. Seule **la
    ///     plus récente par dossier d'origine** est examinée : les précédentes
    ///     décrivent un état que l'utilisateur a déjà dépassé, et le parc en
    ///     compte jusqu'à une dizaine par mod.
    ///   - installedFolder: dossier d'origine → chemin du mod installé, `nil`
    ///     quand le mod n'est plus là. Ce cas relève de la restauration
    ///     complète, pas d'ici.
    ///   - jsonKeys: chemin d'un fichier → ses clés de premier niveau, `nil`
    ///     quand le fichier n'existe pas ou ne se décode pas.
    static func scan(backups: [ModInstallBackup],
                     installedFolder: (String) -> String?,
                     jsonKeys: (String) -> [String]?,
                     candidates: [String] = defaultCandidates) -> [RecoverableFile] {
        var latest: [String: ModInstallBackup] = [:]
        for backup in backups {
            let key = backup.originalFolderName
            if let known = latest[key], known.timestamp >= backup.timestamp { continue }
            latest[key] = backup
        }

        var found: [RecoverableFile] = []
        for (folderName, backup) in latest {
            guard let installedRoot = installedFolder(folderName) else { continue }
            for relativePath in candidates {
                let backupPath = (backup.backupPath as NSString).appendingPathComponent(relativePath)
                guard let backupKeys = jsonKeys(backupPath) else { continue }
                let installedPath = (installedRoot as NSString).appendingPathComponent(relativePath)
                guard let reason = FileRecoveryRules.reason(installedKeys: jsonKeys(installedPath),
                                                            backupKeys: backupKeys) else { continue }
                found.append(RecoverableFile(folderName: folderName,
                                             modName: backup.modMetadata.name,
                                             relativePath: relativePath,
                                             backupPath: backupPath,
                                             installedPath: installedPath,
                                             reason: reason))
            }
        }
        // Ordre stable : le parcours d'un dictionnaire ne l'est pas, et une
        // liste qui se réordonne à chaque rendu est illisible.
        return found.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
}
