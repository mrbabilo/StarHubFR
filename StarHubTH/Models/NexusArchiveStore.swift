import Foundation

/// Une archive Nexus conservée après une installation réussie (X103-C).
///
/// L'identité est `uniqueId` + `version`, **jamais** l'identifiant Nexus :
/// 58 identifiants sont partagés sur le parc de référence et l'id 8828 en
/// couvre trois à lui seul — indexer dessus a déjà effacé les mises à jour de
/// trois mods.
public struct NexusArchiveEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(uniqueId)@\(version)" }
    public let uniqueId: String
    public let version: String
    /// Le nom lisible du mod au moment de l'installation, pour l'écran.
    public let modName: String
    /// Le nom de fichier tel que Nexus l'a servi — il porte souvent la version
    /// et la variante, et c'est ce que l'utilisateur reconnaît.
    public let fileName: String
    public let byteSize: Int64
    public var timestamp: Date

    public init(uniqueId: String, version: String, modName: String,
                fileName: String, byteSize: Int64, timestamp: Date = Date()) {
        self.uniqueId = uniqueId
        self.version = version
        self.modName = modName
        self.fileName = fileName
        self.byteSize = byteSize
        self.timestamp = timestamp
    }
}

/// Garde les archives d'installation Nexus pour qu'un mod supprimé se
/// réinstalle sans retélécharger — hors ligne, et dans sa version exacte.
///
/// **Ce que ce magasin n'est pas** : la corbeille (X103-B) garde le *dossier
/// installé*, avec les `config.json` et `fr.json` de l'utilisateur. Ici on
/// garde le *zip d'origine*, propre. Les deux répondent à des besoins
/// différents ; §8.1 de la roadmap porte le raisonnement.
///
/// Le magasin est **inerte tant que l'utilisateur ne l'a pas activé** : rien
/// n'appelle `keep` sans le réglage. C'est un choix — une fonction qui écrit
/// sur le disque sans qu'on l'ait demandée fait croître l'empreinte en
/// silence.
public final class NexusArchiveStore {

    /// Rétention hybride, identique à celle des sauvegardes d'installation
    /// (`ModInstallBackupManager.cleanupOldBackups`) : deux politiques
    /// différentes pour deux magasins voisins finiraient par diverger.
    private static let maxAge: TimeInterval = 30 * 24 * 60 * 60
    private static let minKept = 5

    private let root: URL
    private let fm = FileManager.default
    /// L'index est relu et réécrit sous verrou : `keep` peut être appelé
    /// depuis la fin d'une installation pendant qu'un écran liste les entrées.
    private let lock = NSLock()

    public init(root: URL) {
        self.root = root
    }

    /// L'emplacement par défaut, à côté des autres magasins de l'app.
    public static func defaultRoot(applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent("StarHubTH")
            .appendingPathComponent("NexusArchives")
    }

    private var indexURL: URL { root.appendingPathComponent("index.json") }
    private var filesDir: URL { root.appendingPathComponent("files") }

    /// Le fichier d'une entrée. Le nom sur disque est dérivé de l'identité, pas
    /// du nom d'origine : un nom servi par Nexus peut porter des caractères que
    /// le système de fichiers traite à sa façon, et deux mods peuvent servir un
    /// fichier de même nom.
    public func fileURL(of entry: NexusArchiveEntry) -> URL {
        let safe = entry.id.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return filesDir.appendingPathComponent(safe).appendingPathExtension("zip")
    }

    // MARK: - Lecture

    /// Les entrées dont le fichier existe réellement, la plus récente d'abord.
    ///
    /// Le disque est la vérité : l'index peut mentir — ménage manuel dans le
    /// Finder, disque plein pendant une écriture. Servir un chemin mort ferait
    /// échouer la réinstallation avec une erreur incompréhensible.
    public func entries() -> [NexusArchiveEntry] {
        lock.lock(); defer { lock.unlock() }
        return loadIndex()
            .filter { fm.fileExists(atPath: fileURL(of: $0).path) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    public func entry(uniqueId: String, version: String) -> NexusArchiveEntry? {
        entries().first { $0.uniqueId == uniqueId && $0.version == version }
    }

    public func totalBytes() -> Int64 {
        entries().reduce(0) { $0 + $1.byteSize }
    }

    // MARK: - Écriture

    /// Copie une archive dans le magasin. **Copie, jamais déplacement** : le
    /// flux d'installation efface l'archive lui-même
    /// (`NexusFileDownload.discardDownloaded`), et la déplacer sous ses pieds
    /// casserait ce ménage.
    @discardableResult
    public func keep(archive: URL, uniqueId: String, version: String,
                     modName: String) throws -> NexusArchiveEntry {
        let size = (try? fm.attributesOfItem(atPath: archive.path)[.size] as? Int64) ?? 0
        let entry = NexusArchiveEntry(
            uniqueId: uniqueId, version: version, modName: modName,
            fileName: archive.lastPathComponent, byteSize: size ?? 0)

        try fm.createDirectory(at: filesDir, withIntermediateDirectories: true)
        let destination = fileURL(of: entry)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: archive, to: destination)

        lock.lock(); defer { lock.unlock() }
        var index = loadIndex()
        index.removeAll { $0.id == entry.id }
        index.append(entry)
        do {
            try saveIndex(index)
        } catch {
            // L'index n'a pas pu être écrit : reprendre la copie plutôt que
            // laisser un fichier que plus rien ne référence.
            try? fm.removeItem(at: destination)
            throw error
        }
        return entry
    }

    public func remove(_ entry: NexusArchiveEntry) {
        try? fm.removeItem(at: fileURL(of: entry))
        lock.lock(); defer { lock.unlock() }
        var index = loadIndex()
        index.removeAll { $0.id == entry.id }
        // Le fichier est déjà parti : un index non réécrit se rattrape au
        // prochain passage, `entries()` ne sert pas une entrée sans fichier.
        try? saveIndex(index)
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        try? fm.removeItem(at: filesDir)
        try? saveIndex([])
    }

    /// Rétention hybride : tout ce qui a moins de 30 jours, plus la plus
    /// récente par mois calendaire au-delà, et jamais moins de cinq archives
    /// quel que soit leur âge. Rend le nombre d'archives effacées.
    @discardableResult
    public func applyRetention() -> Int {
        lock.lock()
        let sorted = loadIndex().sorted { $0.timestamp > $1.timestamp }
        lock.unlock()
        guard sorted.count > Self.minKept else { return 0 }

        var kept = Set<String>(sorted.prefix(Self.minKept).map(\.id))
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        for e in sorted where e.timestamp >= cutoff { kept.insert(e.id) }

        var seenMonths = Set<String>()
        let month = DateFormatter()
        month.dateFormat = "yyyy-MM"
        month.locale = Locale(identifier: "en_US_POSIX")
        for e in sorted where e.timestamp < cutoff {
            if seenMonths.insert(month.string(from: e.timestamp)).inserted {
                kept.insert(e.id)
            }
        }

        let doomed = sorted.filter { !kept.contains($0.id) }
        guard !doomed.isEmpty else { return 0 }
        // L'entrée ne quitte l'index qu'une fois son fichier confirmé parti —
        // même règle que `ModInstallBackupManager`, pour que l'index ne diverge
        // jamais en silence de ce que porte le disque.
        var removed = Set<String>()
        for e in doomed {
            let url = fileURL(of: e)
            if fm.fileExists(atPath: url.path) {
                do { try fm.removeItem(at: url); removed.insert(e.id) } catch { continue }
            } else {
                removed.insert(e.id)
            }
        }
        guard !removed.isEmpty else { return 0 }
        lock.lock(); defer { lock.unlock() }
        var index = loadIndex()
        index.removeAll { removed.contains($0.id) }
        try? saveIndex(index)
        return removed.count
    }

    /// Réservé aux tests : repose une entrée avec un horodatage choisi, pour
    /// éprouver la rétention sans attendre trente jours.
    public func replaceForTesting(_ entry: NexusArchiveEntry) {
        lock.lock(); defer { lock.unlock() }
        var index = loadIndex()
        index.removeAll { $0.id == entry.id }
        index.append(entry)
        try? saveIndex(index)
    }

    // MARK: - Index

    private func loadIndex() -> [NexusArchiveEntry] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([NexusArchiveEntry].self, from: data)) ?? []
    }

    /// Écrit l'index, et **remonte son échec**.
    ///
    /// Un `try?` ici serait le pire endroit du fichier pour en mettre un : une
    /// archive copiée dont l'index n'a pas été écrit est un fichier invisible
    /// qui pèse — exactement l'occupation disque muette que ce lot cherche à
    /// éviter. `keep` propage donc l'erreur, et l'appelant sait que l'archive
    /// n'a pas été conservée.
    private func saveIndex(_ entries: [NexusArchiveEntry]) throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: indexURL, options: .atomic)
    }
}
