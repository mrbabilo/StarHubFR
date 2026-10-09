import Foundation

/// La quarantaine du réparateur lue sur le disque — sortie de `ModTrash.swift`
/// pour le garder sous le plafond de taille du cliquet.
extension ModTrash {
    /// Une entrée de premier niveau d'une quarantaine du réparateur.
    ///
    /// Le réparateur recrée le chemin relatif sous `_Trash_<horodatage>/` :
    /// l'entrée de tête peut donc n'être qu'un **conteneur** (le dossier d'un
    /// mod dont un sous-dossier a été écarté), le mod lui-même restant dans
    /// `Mods/`. `children` et `stillInMods` le disent — sans eux, la page
    /// ferait croire à un mod disparu (cas réel `.PersonalEffectsRedux`,
    /// 2026-10-09).
    struct QuarantineEntry: Equatable, Identifiable {
        /// Le dossier `_Trash_<horodatage>` qui la contient.
        let folder: String
        /// Le nom de l'entrée de tête, tel que sur le disque.
        let name: String
        /// Ses enfants directs si c'est un dossier, triés ; vide sinon.
        let children: [String]
        /// `Mods/<name>` existe encore : seul un morceau du mod a été écarté.
        let stillInMods: Bool
        /// L'horodatage du dossier de quarantaine, `nil` s'il est illisible.
        let date: Date?

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
            return listing(dir, fm).sorted().map { name in
                let entryPath = (dir as NSString).appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                let children = fm.fileExists(atPath: entryPath, isDirectory: &isDirectory)
                    && isDirectory.boolValue ? listing(entryPath, fm).sorted() : []
                // Conteneur seulement : un fichier écarté (`.DS_Store`) que le
                // Finder recrée dans `Mods/` n'est pas « un mod toujours en place ».
                let stillInMods = !children.isEmpty
                    && fm.fileExists(atPath: (modsPath as NSString).appendingPathComponent(name))
                return QuarantineEntry(folder: folder, name: name, children: children,
                                       stillInMods: stillInMods, date: date)
            }
        }
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
