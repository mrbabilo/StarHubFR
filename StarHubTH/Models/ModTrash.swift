import Foundation

/// X103-B — la corbeille des mods supprimés.
///
/// Un mod « supprimé » ne disparaît plus : il est déplacé sous
/// `Mods/_Trash_<yyyyMMdd_HHmmss>/` — le **même préfixe** que la quarantaine
/// du réparateur, que le scanner saute déjà au niveau 1 (un mod mis à la
/// corbeille ne peut donc jamais revenir dans la liste). Une corbeille ne
/// sert à rien si elle se vide toute seule : **aucune purge automatique**,
/// jamais une heuristique silencieuse (leçon X25) — les deux sorties sont
/// explicites : « remettre » (en désactivé, §5.6) ou « supprimer ».
enum ModTrash {

    /// Un dossier de corbeille = un événement de suppression (deux
    /// suppressions à la seconde partagent le même dossier, le compteur de
    /// collision sépare les homonymes — même fail-safety par item que le
    /// réparateur).
    struct Event: Identifiable, Equatable {
        /// Nom du dossier, ex. `_Trash_20260909_101112`.
        let folderName: String
        /// Date lue dans le nom, `nil` si le suffixe n'est pas une date.
        let date: Date?
        /// Chemins relatifs des mods posés dans cet événement (le nom
        /// logique, jamais pointé ; les composants de pack gardent leur
        /// chemin `Pack/Composant`).
        let entries: [String]

        var id: String { folderName }
    }

    // MARK: - Nommage

    /// Fichier marqueur posé à la racine de chaque événement de corbeille
    /// **utilisateur**. Le préfixe `_Trash_` est partagé avec la quarantaine
    /// du réparateur (le scanner ne saute qu'un préfixe) : sans ce marqueur,
    /// la corbeille listerait — et « Vider » effacerait — le travail du
    /// réparateur. Un dossier `_Trash_*` sans marqueur n'est pas à nous.
    static let eventMarker = ".starhubfr-user-trash"

    /// Pose le marqueur. Appelé **avant** le déplacement du mod : si le
    /// disque refuse cette écriture, aucun mod n'a encore bougé.
    static func markEvent(eventDir: String) throws {
        let markerPath = (eventDir as NSString).appendingPathComponent(eventMarker)
        try Data().write(to: URL(fileURLWithPath: markerPath))
    }

    static func isUserEvent(modsPath: String, event: String,
                            fm: FileManager = .default) -> Bool {
        guard isTrashFolder(event) else { return false }
        let markerPath = (modsPath as NSString)
            .appendingPathComponent((event as NSString).appendingPathComponent(eventMarker))
        return fm.fileExists(atPath: markerPath)
    }

    /// Le même format que `ModFolderRepairer.nowStamp` : lisible dans
    /// Finder, trié chronologiquement, locale posée (piège §4.7).
    static func makeStamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    static func trashFolderName(stamp: String) -> String {
        "\(ModFolderRepairer.trashPrefix)\(stamp)"
    }

    /// Le garde du scanner : ne sauter QUE les dossiers qui portent le
    /// préfixe — jamais un mod légitime dont le nom commencerait par
    /// autre chose.
    static func isTrashFolder(_ name: String) -> Bool {
        name.hasPrefix(ModFolderRepairer.trashPrefix)
    }

    // MARK: - Déposer

    /// Le chemin où poser un mod supprimé dans son événement. Le nom est le
    /// **logique** (`folderName`, jamais pointé — c'est lui que « remettre »
    /// relira) ; le chemin imbriqué d'un composant de pack est préservé.
    /// Deux mods homonymes supprimés dans le même événement se séparent par
    /// compteur, jamais par écrasement.
    static func destination(eventDir: String, logicalFolderName: String,
                            fm: FileManager = .default) -> String {
        let candidate = (eventDir as NSString).appendingPathComponent(logicalFolderName)
        guard fm.fileExists(atPath: candidate) else { return candidate }
        let parent = (candidate as NSString).deletingLastPathComponent
        let leaf = (candidate as NSString).lastPathComponent
        for index in 1...99 {
            let numbered = (parent as NSString)
                .appendingPathComponent("\(leaf)_\(index)")
            if !fm.fileExists(atPath: numbered) { return numbered }
        }
        // Cent homonymes d'affilée n'arrive pas ; s'il fallait trancher, un
        // identifiant unique vaut mieux qu'un écrasement.
        return (parent as NSString)
            .appendingPathComponent("\(leaf)_\(UUID().uuidString)")
    }

    // MARK: - Remettre

    /// Le chemin de retour : `Mods/<chemin relatif>` avec le **point forcé
    /// sur la dernière composante** — un mod remis revient désactivé (§5.6,
    /// même règle que la restauration de sauvegarde), l' utilisateur le
    /// réactive explicitement. Une collision (le nom est repris) se décale
    /// sur un suffixe horodaté — jamais un écrasement.
    static func restoreDestination(modsPath: String, entryRelativePath: String,
                                   stamp: String, fm: FileManager = .default) -> String {
        let posix = entryRelativePath.replacingOccurrences(of: "\\", with: "/")
        let parentRelative = (posix as NSString).deletingLastPathComponent
        let leaf = (posix as NSString).lastPathComponent
        let disabledLeaf = leaf.hasPrefix(".") ? leaf : "." + leaf

        func path(_ disabledLeaf: String) -> String {
            let relative = parentRelative.isEmpty
                ? disabledLeaf
                : (parentRelative as NSString).appendingPathComponent(disabledLeaf)
            return (modsPath as NSString).appendingPathComponent(relative)
        }

        var candidate = path(disabledLeaf)
        guard fm.fileExists(atPath: candidate) else { return candidate }
        for index in 1...99 {
            candidate = path("\(disabledLeaf)_\(stamp)_\(index)")
            if !fm.fileExists(atPath: candidate) { return candidate }
        }
        return path("\(disabledLeaf)_\(stamp)_\(UUID().uuidString)")
    }

    // MARK: - Lister

    /// Les événements de corbeille **utilisateur** (marqués), du plus récent
    /// au plus ancien. Les quarantaines du réparateur — même préfixe, sans
    /// marqueur — ne sont pas de la corbeille : les lister proposerait de
    /// « remettre » le junk que le réparateur vient d'écarter. Un événement
    /// sans entrée (tout a été remis ou supprimé item par item) n'est pas
    /// listé — la corbeille vide ne s'affiche pas.
    static func events(modsPath: String, fm: FileManager = .default) -> [Event] {
        let names = (try? fm.contentsOfDirectory(atPath: modsPath))?
            .filter(isTrashFolder)
            .filter { isUserEvent(modsPath: modsPath, event: $0, fm: fm) } ?? []
        let parser = DateFormatter()
        parser.dateFormat = "yyyyMMdd_HHmmss"
        parser.locale = Locale(identifier: "en_US_POSIX")

        return names
            .map { name -> (Event, sortKey: String) in
                let dir = (modsPath as NSString).appendingPathComponent(name)
                let suffix = String(name.dropFirst(ModFolderRepairer.trashPrefix.count))
                let entries = (try? fm.subpathsOfDirectory(atPath: dir))?
                    .filter { sub in
                        // Le marqueur n'est pas une entrée, et les
                        // sous-chemins intermédiaires (`Pack/` d'un
                        // composant) non plus : on liste les composantes
                        // de tête — c'est ce que « remettre » remet.
                        sub != eventMarker && !sub.contains("/")
                    } ?? []
                return (Event(folderName: name,
                              date: parser.date(from: suffix),
                              entries: entries.sorted()),
                        sortKey: name)
            }
            // Un événement sans entrée (tout a été remis ou purgé item par
            // item) n'est pas une corbeille à montrer.
            .filter { !$0.0.entries.isEmpty }
            .sorted { $0.sortKey > $1.sortKey }
            .map(\.0)
    }

    // MARK: - Purger

    /// Supprime une entrée, puis l'événement s'il est vide — une corbeille
    /// sans contenu ne laisse pas de dossier fantôme.
    static func purgeEntry(modsPath: String, event: String, entry: String,
                           fm: FileManager = .default) throws {
        guard isUserEvent(modsPath: modsPath, event: event, fm: fm) else {
            throw CocoaError(.fileNoSuchFile,
                             userInfo: [NSFilePathErrorKey: event])
        }
        // Une entrée vide ou « . » désignerait l'événement entier — jamais
        // une cible de purge nominative.
        let trimmed = entry.trimmingCharacters(in: ["/"])
        guard !trimmed.isEmpty, trimmed != "." else {
            throw CocoaError(.fileReadInvalidFileName,
                             userInfo: [NSFilePathErrorKey: entry])
        }
        let eventDir = (modsPath as NSString).appendingPathComponent(event)
        let entryPath = (eventDir as NSString).appendingPathComponent(trimmed)
        // Le chemin demandé doit rester DANS l'événement : un `..` ne doit
        // jamais franchir la corbeille (leçon zip-slip, côté purge).
        let standardized = (entryPath as NSString).standardizingPath
        guard standardized.hasPrefix((eventDir as NSString).standardizingPath) else {
            throw CocoaError(.fileReadInvalidFileName,
                             userInfo: [NSFilePathErrorKey: entry])
        }
        try fm.removeItem(atPath: entryPath)
        discardEventIfEmpty(modsPath: modsPath, event: event, fm: fm)
    }

    /// Après une remise ou une purge (l'entrée a disparu), l'événement vidé
    /// disparaît — le marqueur ne compte pas comme du contenu.
    static func discardEventIfEmpty(modsPath: String, event: String,
                                    fm: FileManager = .default) {
        guard isTrashFolder(event) else { return }
        let eventDir = (modsPath as NSString).appendingPathComponent(event)
        let rest = ((try? fm.contentsOfDirectory(atPath: eventDir)) ?? [])
            .filter { $0 != eventMarker }
        if rest.isEmpty {
            try? fm.removeItem(atPath: eventDir)
        }
    }

    /// Vide la corbeille **utilisateur** — les quarantaines du réparateur
    /// (même préfixe, sans marqueur) ne sont pas de la corbeille et restent
    /// le domaine du réparateur. Retourne le nombre d'événements supprimés.
    static func purgeAll(modsPath: String, fm: FileManager = .default) throws -> Int {
        let names = (try? fm.contentsOfDirectory(atPath: modsPath))?
            .filter(isTrashFolder)
            .filter { isUserEvent(modsPath: modsPath, event: $0, fm: fm) } ?? []
        for name in names {
            try fm.removeItem(atPath: (modsPath as NSString).appendingPathComponent(name))
        }
        return names.count
    }
}
