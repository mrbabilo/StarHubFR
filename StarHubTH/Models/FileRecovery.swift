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
    /// La racine du mod installé. L'écriture y remonte les droits quand le
    /// dossier est en lecture seule, et **s'y arrête** : jamais au-dessus.
    let installedRoot: String
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
                                             installedRoot: installedRoot,
                                             reason: reason))
            }
        }
        // Ordre stable : le parcours d'un dictionnaire ne l'est pas, et une
        // liste qui se réordonne à chaque rendu est illisible.
        return found.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
}

/// Écrit un fichier récupéré dans le dossier d'un mod installé.
///
/// Ce que la copie a de particulier ici : **le dossier du mod est souvent en
/// lecture seule**. `unzip` et `unrar` restituent les modes de l'archive, et
/// une bonne part du parc a ses dossiers en `0555` — signalé sur
/// `[CP] Toothless Pet`, dont `i18n/` était `dr-xr-xr-x`. C'est le même piège
/// qui avait fait échouer les mises à jour de mods (X7).
///
/// Les autorisations sont **rendues telles qu'on les a trouvées** : un mod
/// reste comme son auteur l'a empaqueté, et récupérer une traduction ne doit
/// pas laisser derrière soi un dossier plus ouvert qu'avant.
enum RecoveredFileWriter {
    /// - Parameters:
    ///   - backupPath: le fichier à copier, dans la sauvegarde.
    ///   - installedPath: où l'écrire, dans le mod installé.
    ///   - modRoot: la racine du mod — la remontée des droits s'y arrête, on
    ///     ne touche jamais aux autorisations de `Mods/` ni au-dessus.
    static func write(from backupPath: String, to installedPath: String, modRoot: String) throws {
        let fm = FileManager.default
        // Du parent du fichier jusqu'à la racine du mod : ce sont les dossiers
        // qu'il faudra pouvoir écrire, soit pour créer `i18n/`, soit pour y
        // remplacer un fichier.
        var chain: [String] = []
        var current = (installedPath as NSString).deletingLastPathComponent
        while current.count >= modRoot.count, current.hasPrefix(modRoot) {
            chain.append(current)
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }

        var restore: [(path: String, mode: NSNumber)] = []
        defer {
            // Dans le sens inverse : le parent redevient lecture seule après
            // ses enfants, sinon on ne pourrait plus les atteindre.
            for entry in restore.reversed() {
                try? fm.setAttributes([.posixPermissions: entry.mode], ofItemAtPath: entry.path)
            }
        }
        func grantWrite(_ path: String) {
            guard let mode = (try? fm.attributesOfItem(atPath: path))?[.posixPermissions] as? NSNumber
            else { return }
            var isDirectory: ObjCBool = false
            fm.fileExists(atPath: path, isDirectory: &isDirectory)
            // Un dossier a aussi besoin de `x` pour être traversé pendant qu'on
            // y écrit.
            let wanted = mode.uint16Value | (isDirectory.boolValue ? 0o700 : 0o600)
            guard wanted != mode.uint16Value else { return }
            if (try? fm.setAttributes([.posixPermissions: NSNumber(value: wanted)],
                                      ofItemAtPath: path)) != nil {
                restore.append((path, mode))
            }
        }

        for path in chain.reversed() where fm.fileExists(atPath: path) { grantWrite(path) }

        let parent = (installedPath as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
        if fm.fileExists(atPath: installedPath) {
            grantWrite(installedPath)
            try fm.removeItem(atPath: installedPath)
        }
        try fm.copyItem(atPath: backupPath, toPath: installedPath)
    }
}
