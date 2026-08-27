import Foundation

/// Ce qui doit changer dans un mod pour qu'une couverture déjà mesurée cesse
/// d'être valable.
///
/// Trois grandeurs, toutes lues dans les **attributs** des fichiers de
/// traduction — jamais dans leur contenu. Mesuré sur le parc réel : relever
/// ces attributs pour les 592 dossiers `i18n` coûte **0,11 s**, quand analyser
/// les fichiers eux-mêmes en coûte **15,7**. C'est tout l'intérêt de
/// l'empreinte : payer un centième du prix pour savoir si le reste est encore
/// à payer.
///
/// Le nombre de fichiers **et** leur taille cumulée **et** la date la plus
/// récente : une seule de ces grandeurs se laisserait tromper — traduire une
/// clé sans changer la longueur du fichier arrive (`"Yes"` → `"Oui"` fait
/// exactement la même taille), et un `touch` sans modification est courant
/// après une copie.
struct TranslationStamp: Codable, Equatable, Sendable {
    let fileCount: Int
    let totalSize: Int
    /// Arrondie à la seconde : les dates des systèmes de fichiers ne portent
    /// pas la même précision d'un support à l'autre, et un aller-retour par
    /// JSON n'en garde pas les décimales. Sans cet arrondi, une empreinte
    /// relue serait *toujours* différente de celle qu'on vient de calculer,
    /// et le cache ne servirait jamais.
    let newestModified: Int

    init(fileCount: Int, totalSize: Int, newestModified: Int) {
        self.fileCount = fileCount
        self.totalSize = totalSize
        self.newestModified = newestModified
    }

    /// L'empreinte des fichiers de traduction contenus dans ces dossiers.
    ///
    /// `nil` quand il n'y a aucun fichier à empreindre : il n'y a alors rien à
    /// mettre en cache, et une empreinte vide vaudrait pour n'importe quel
    /// autre mod sans traduction.
    ///
    /// Les sous-dossiers sont inclus — un mod en *layout B* range ses fichiers
    /// dans `i18n/fr/`. La règle est volontairement plus large que celle du
    /// chargeur : mieux vaut invalider une fois de trop qu'annoncer un
    /// pourcentage périmé.
    static func of(directories: [URL], fileManager: FileManager = .default) -> TranslationStamp? {
        var count = 0, size = 0
        var newest = 0

        func absorb(_ files: [URL]) {
            for file in files {
                guard let values = try? file.resourceValues(forKeys: [.fileSizeKey,
                                                                     .contentModificationDateKey])
                else { continue }
                count += 1
                size += values.fileSize ?? 0
                if let date = values.contentModificationDate {
                    newest = max(newest, Int(date.timeIntervalSince1970))
                }
            }
        }

        for directory in directories {
            let entries = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey,
                                             .contentModificationDateKey])) ?? []
            let isDirectory = { (url: URL) in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            absorb(entries.filter { !isDirectory($0) })
            for sub in entries.filter(isDirectory) {
                let files = (try? fileManager.contentsOfDirectory(
                    at: sub,
                    includingPropertiesForKeys: [.fileSizeKey,
                                                 .contentModificationDateKey])) ?? []
                absorb(files.filter { !isDirectory($0) })
            }
        }

        return count == 0 ? nil : TranslationStamp(fileCount: count, totalSize: size,
                                                   newestModified: newest)
    }
}

/// Les couvertures françaises déjà mesurées, gardées d'une session à l'autre.
///
/// Sans ce cache, ouvrir la page des profils coûtait **15,7 s** de lecture
/// disque à chaque lancement — le prix d'analyser les fichiers de traduction
/// de tout le parc. Avec lui, seuls les mods dont l'empreinte a bougé sont
/// relus : 2,6 s quand rien n'a changé, et c'est le parcours des dossiers qui
/// les explique, pas l'analyse.
///
/// Le cache est indexé par `UniqueID` **en minuscules**, comme partout où un
/// identifiant sert de clé, et non par dossier : un mod renommé garde son
/// travail de traduction.
enum TranslationCoverageCache {
    /// Une couverture mesurée, avec l'empreinte qui la date.
    struct Entry: Codable, Equatable, Sendable {
        let stamp: TranslationStamp
        let total: Int
        let translated: Int

        init(stamp: TranslationStamp, total: Int, translated: Int) {
            self.stamp = stamp
            self.total = total
            self.translated = translated
        }
    }

    /// L'entrée reste valable tant que l'empreinte du mod n'a pas bougé.
    static func valid(_ entry: Entry?, against stamp: TranslationStamp?) -> Entry? {
        guard let entry, let stamp, entry.stamp == stamp else { return nil }
        return entry
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory,
                                          in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("StarHubTH", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ProfileTranslationCoverage.json")
    }

    /// Relit le cache. Un fichier absent, tronqué ou d'une version antérieure
    /// rend une table vide : le pire qu'il puisse arriver est de tout
    /// remesurer, jamais d'afficher un chiffre faux.
    static func load(from url: URL, fileManager: FileManager = .default) -> [String: Entry] {
        guard let data = fileManager.contents(atPath: url.path),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }

    /// Écrit le cache. Silencieux en cas d'échec : perdre le cache coûte une
    /// remesure, pas une donnée de l'utilisateur.
    static func save(_ entries: [String: Entry], to url: URL) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Les entrées dont le mod n'est plus dans le parc, à oublier.
    ///
    /// Sans ce nettoyage, le fichier ne ferait que grossir : chaque mod
    /// désinstallé y laisserait son empreinte pour toujours.
    static func pruned(_ entries: [String: Entry],
                       keeping installedUniqueIds: Set<String>) -> [String: Entry] {
        let keep = Set(installedUniqueIds.map { $0.lowercased() })
        return entries.filter { keep.contains($0.key) }
    }
}
