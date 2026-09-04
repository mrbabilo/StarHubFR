import Foundation

/// La règle de l'écran « Entretien » : ce que l'app occupe, ce qu'une purge
/// libérerait, et ce qu'elle ferait perdre.
///
/// **Pur, sans accès disque.** Le ViewModel lit le disque une fois et passe ici
/// ce qu'il a relevé. C'est ce qui rend la règle éprouvable — et il s'agit de
/// code qui supprime des fichiers.
public enum MaintenanceInventory {

    /// Un fichier écrit par l'utilisateur, relatif à la racine de la sauvegarde.
    ///
    /// Une traduction **d'auteur** (`i18n/default.json`, `i18n/de.json`) n'en est
    /// pas une : elle revient avec le mod. Seul compte ce que l'utilisateur a posé,
    /// et le ViewModel le sait par `InstalledTranslationStore`.
    public struct UserFile: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case config, translation }
        public let relativePath: String
        public let kind: Kind

        public init(relativePath: String, kind: Kind) {
            self.relativePath = relativePath
            self.kind = kind
        }
    }

    /// Une sauvegarde d'installation, réduite à ce que la décision demande.
    public struct BackupEntry: Equatable, Sendable {
        /// Le dossier de session sous `Backups/ModInstalls/backups/`.
        public let id: String
        /// `originalFolderName` — nom **logique**, éventuellement `Pack/Composant`.
        public let modFolder: String
        public let timestamp: Date
        public let sizeBytes: Int64
        public let userFiles: [UserFile]

        public init(id: String, modFolder: String, timestamp: Date,
                    sizeBytes: Int64, userFiles: [UserFile]) {
            self.id = id
            self.modFolder = modFolder
            self.timestamp = timestamp
            self.sizeBytes = sizeBytes
            self.userFiles = userFiles
        }
    }

    /// Ce que le mod porte aujourd'hui. `presentFiles` vaut `nil` quand le mod
    /// n'est plus installé du tout — et c'est le cas le plus grave, puisque rien
    /// ne subsiste ailleurs.
    public struct InstalledState: Equatable, Sendable {
        public let presentFiles: Set<String>?

        public init(presentFiles: Set<String>?) {
            self.presentFiles = presentFiles
        }
    }

    public enum Protection: Equatable, Sendable {
        case none
        /// Les fichiers dont cette sauvegarde est la seule copie.
        case soleCopy([UserFile])
    }

    /// **La présence tranche, jamais le contenu.** Tant que le mod vit et porte
    /// son `config.json`, la sauvegarde n'est la seule copie de rien : elle porte
    /// un état antérieur, ce qui est exactement son rôle. Comparer les octets
    /// protégerait 160 sauvegardes du parc pour un cas utile.
    public static func protection(of entry: BackupEntry,
                                  installed: InstalledState) -> Protection {
        guard !entry.userFiles.isEmpty else { return .none }
        let present = installed.presentFiles ?? []
        let missing = entry.userFiles.filter { !present.contains($0.relativePath) }
        return missing.isEmpty ? .none : .soleCopy(missing)
    }

    /// Ce qu'une politique retirerait, protections déduites.
    public struct PurgePlan: Equatable, Sendable {
        public let doomed: [BackupEntry]
        public let freedBytes: Int64
        public let protectedCount: Int

        public init(doomed: [BackupEntry], freedBytes: Int64, protectedCount: Int) {
            self.doomed = doomed
            self.freedBytes = freedBytes
            self.protectedCount = protectedCount
        }
    }

    /// Les sauvegardes à retirer pour ne garder que `keepPerMod` par mod.
    ///
    /// Trois règles, dans cet ordre :
    /// 1. **Une sauvegarde protégée ne part jamais** et ne consomme pas de place
    ///    dans le quota — elle survit *en plus*, sinon protéger un mod reviendrait
    ///    à supprimer sa dernière sauvegarde libre.
    /// 2. Les plus **récentes** sont gardées : c'est leur date qui répond à « ce
    ///    que j'avais avant ma dernière mise à jour ».
    /// 3. `keepPerMod` est borné à 1 ici, pas chez l'appelant : zéro gardé
    ///    effacerait tout l'historique d'un mod.
    public static func plan(keepPerMod: Int,
                            entries: [BackupEntry],
                            protections: [String: Protection]) -> PurgePlan {
        let keep = max(1, keepPerMod)
        var doomed: [BackupEntry] = []
        var protectedCount = 0

        for (_, group) in Dictionary(grouping: entries, by: \.modFolder) {
            var free: [BackupEntry] = []
            for entry in group {
                if case .soleCopy = protections[entry.id] ?? .none {
                    protectedCount += 1
                } else {
                    free.append(entry)
                }
            }
            let ordered = free.sorted { $0.timestamp > $1.timestamp }
            doomed.append(contentsOf: ordered.dropFirst(keep))
        }

        return PurgePlan(doomed: doomed,
                         freedBytes: doomed.reduce(0) { $0 + $1.sizeBytes },
                         protectedCount: protectedCount)
    }
}
