import Foundation

/// La quarantaine du réparateur lue sur le disque — sortie de `ModTrash.swift`
/// pour le garder sous le plafond de taille du cliquet.
extension ModTrash {
    /// Une entrée de premier niveau d'une quarantaine du réparateur.
    ///
    /// Le réparateur recrée le chemin relatif sous `_Trash_<horodatage>/` :
    /// l'entrée de tête peut donc n'être qu'un **conteneur** (le dossier d'un
    /// mod dont un morceau a été écarté), le mod lui-même restant dans
    /// `Mods/`. `removedItems` et `stillInMods` le disent — sans eux, la page
    /// ferait croire à un mod disparu (cas réel `.PersonalEffectsRedux`,
    /// 2026-10-09 : deux `.DS_Store` retirés de l'intérieur, mod intact).
    struct QuarantineEntry: Equatable, Identifiable {
        /// Le dossier `_Trash_<horodatage>` qui la contient.
        let folder: String
        /// Le nom de l'entrée de tête, tel que sur le disque.
        let name: String
        /// Ce qui a réellement été écarté sous elle : ses **feuilles** (fichiers
        /// et dossiers vides), en chemins relatifs, triées. Les dossiers
        /// intermédiaires ne sont que le squelette recréé par `moveToTrash` —
        /// les lister faisait lire « [JA] Personal Effects » quand seuls ses
        /// `.DS_Store` étaient partis. Vide pour une entrée-fichier.
        let removedItems: [String]
        /// `Mods/<name>` existe encore : seul un morceau du mod a été écarté.
        let stillInMods: Bool
        /// L'horodatage du dossier de quarantaine, `nil` s'il est illisible.
        let date: Date?
        /// Pourquoi le réparateur l'a écarté, lu dans le rapport persistant du
        /// `_Trash_` ; vide pour une quarantaine d'avant ce rapport.
        var reasons: [String] = []

        var id: String { folder + "/" + name }
    }

    /// Les entrées de quarantaine **telles que le badge les compte** : une
    /// seule source pour la liste et le compte (X114 avait fait lire le disque
    /// au badge, la page lisait encore le rapport en mémoire — perdu au
    /// relancement ou à la réparation suivante, la page restait vide sous un
    /// badge à 1). Du plus récent au plus ancien, puis par nom.
    static func quarantineEntries(gameDir: String,
                                  fm: FileManager = .default) -> [QuarantineEntry] {
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let parser = DateFormatter()
        parser.dateFormat = "yyyyMMdd_HHmmss"
        parser.locale = Locale(identifier: "en_US_POSIX")
        return listing(gameDir, fm).filter(isTrashFolder).sorted(by: >).flatMap { folder in
            let dir = (gameDir as NSString).appendingPathComponent(folder)
            let date = parser.date(from: String(folder.dropFirst(ModFolderRepairer.trashPrefix.count)))
            let saved = savedReport(in: dir, fm)
            return listing(dir, fm).filter { $0 != ModFolderRepairer.reportFileName }.sorted().map { name in
                let entryPath = (dir as NSString).appendingPathComponent(name)
                let removedItems = leaves(under: entryPath, fm)
                // Conteneur seulement : un fichier écarté (`.DS_Store`) que le
                // Finder recrée dans `Mods/` n'est pas « un mod toujours en place ».
                let stillInMods = !removedItems.isEmpty
                    && fm.fileExists(atPath: (modsPath as NSString).appendingPathComponent(name))
                // Rattachement par la première composante du chemin relatif :
                // le réparateur recrée ce chemin sous le `_Trash_`.
                let reasons = saved
                    .filter { $0.relativePath.split(separator: "/").first.map(String.init) == name }
                    .map(\.reason)
                return QuarantineEntry(folder: folder, name: name, removedItems: removedItems,
                                       stillInMods: stillInMods, date: date, reasons: reasons)
            }
        }
    }

    /// Les feuilles d'un dossier, en chemins relatifs : fichiers et dossiers
    /// vides. L'énumérateur rend des chemins relatifs (pas de piège
    /// `/var` → `/private/var`) et ne saute pas les fichiers cachés — voulu,
    /// les `.DS_Store` le sont. Vide pour un fichier ou un dossier absent.
    fileprivate static func leaves(under path: String, _ fm: FileManager) -> [String] {
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
              let walker = fm.enumerator(atPath: path) else { return [] }
        var found: [String] = []
        while let relative = walker.nextObject() as? String {
            let full = (path as NSString).appendingPathComponent(relative)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: full, isDirectory: &isDir)
            if !isDir.boolValue || listing(full, fm).isEmpty { found.append(relative) }
        }
        return found.sorted()
    }

    /// Le rapport persistant d'un `_Trash_`, vide s'il manque (quarantaine
    /// d'avant ce rapport) ou s'il est illisible — on perd la raison, pas la liste.
    fileprivate static func savedReport(in trashDir: String, _ fm: FileManager) -> [ModFolderRepairer.Item] {
        let path = (trashDir as NSString).appendingPathComponent(ModFolderRepairer.reportFileName)
        guard let data = fm.contents(atPath: path) else { return [] }
        do { return try JSONDecoder().decode([ModFolderRepairer.Item].self, from: data) } catch { return [] }
    }

    /// Le contenu d'un dossier, vide s'il est illisible ou absent — la
    /// quarantaine est un constat, pas une opération : rien à signaler.
    fileprivate static func listing(_ path: String, _ fm: FileManager) -> [String] {
        do { return try fm.contentsOfDirectory(atPath: path) } catch { return [] }
    }
}

extension ModTrash {
    /// Les entrées que le rapport en mémoire ne couvre pas : il ne décrit que
    /// son propre `_Trash_` (`trashPath`, nil quand rien n'a été déplacé).
    /// Sans ce filtre, une quarantaine d'une session précédente disparaissait
    /// de la page dès qu'un rapport neuf existait — badge à 3, page à 2.
    static func entries(_ entries: [QuarantineEntry],
                        outsideReportedTrash trashPath: String?) -> [QuarantineEntry] {
        guard let trashPath else { return entries }
        let reported = (trashPath as NSString).lastPathComponent
        return entries.filter { $0.folder != reported }
    }
}
