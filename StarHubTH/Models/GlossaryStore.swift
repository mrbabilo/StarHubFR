import Foundation

/// Tâche 9 du plan P2b — où et comment lire les sources du glossaire
/// (spec §4-§5). XNB du jeu d'abord, dossier unpacked de StardewXnbHack en
/// repli : la même architecture que la référence.
public enum GlossarySource {

    public enum Kind: Equatable {
        /// `<jeu>/Content/Strings` — les `.xnb` natifs, LZX inclus.
        case xnbStrings(URL)
        /// `<jeu>/Content (unpacked)/Strings` — les `.json` de StardewXnbHack.
        case unpackedStrings(URL)

        var folder: URL {
            switch self {
            case .xnbStrings(let url), .unpackedStrings(let url): url
            }
        }

        var fileExtension: String {
            switch self {
            case .xnbStrings: "xnb"
            case .unpackedStrings: "json"
            }
        }
    }

    /// Cherche les sources du glossaire autour du dossier du jeu, dans
    /// l'ordre : `Content/Strings` (jeu configuré sur `…/Contents/Resources`),
    /// `Resources/Content/Strings` (jeu sur `…/Contents`),
    /// `../Resources/Content/Strings` (jeu sur `…/Contents/MacOS`, le
    /// dossier de l'exécutable), puis `Content (unpacked)/Strings`. Un
    /// dossier vide ou absent est ignoré ; rend `nil` si rien n'est
    /// exploitable.
    public static func resolve(gameFolder: URL, fileManager: FileManager = .default) -> Kind? {
        let candidates = [
            gameFolder.appendingPathComponent("Content/Strings"),
            gameFolder.appendingPathComponent("Resources/Content/Strings"),
            gameFolder.deletingLastPathComponent()
                .appendingPathComponent("Resources/Content/Strings"),
        ]
        for folder in candidates where hasFiles(folder, extension: "xnb", fileManager: fileManager) {
            return .xnbStrings(folder)
        }
        let unpacked = gameFolder.appendingPathComponent("Content (unpacked)/Strings")
        if hasFiles(unpacked, extension: "json", fileManager: fileManager) {
            return .unpackedStrings(unpacked)
        }
        return nil
    }

    /// Ce qu'un asset a rendu. Un fichier **absent** n'est pas une erreur
    /// (spec §5 : toutes les versions du jeu n'ont pas toutes les tables) ;
    /// un fichier **présent mais illisible** en est une, et la confondre
    /// avec l'absence faisait sortir le glossaire amputé d'une table
    /// entière, avec un décompte rassurant et rien au journal.
    public enum LoadOutcome: Equatable, Sendable {
        case loaded([String: String])
        case absent
        case unreadable
    }

    /// La map d'un asset pour une langue : `<asset>.xnb` / `<asset>.json`
    /// quand `language` est vide (anglais), `<asset>.fr-FR.xnb` /
    /// `<asset>.fr-FR.json` sinon.
    public static func read(asset: String, language: String,
                            from kind: Kind,
                            fileManager: FileManager = .default) -> LoadOutcome {
        let suffix = language.isEmpty ? "" : ".\(language)"
        let file = kind.folder.appendingPathComponent("\(asset)\(suffix).\(kind.fileExtension)")
        guard let data = try? Data(contentsOf: file) else { return .absent }
        let map: [String: String]?
        switch kind {
        case .xnbStrings:
            map = try? XnbStringDictionaryReader.read(data)
        case .unpackedStrings:
            // StardewXnbHack écrit du JSON standard ; le parseur permissif
            // d'i18n le lit, tolérances en plus (commentaires, BOM…).
            map = try? I18nLenientParser.parse(data)
        }
        return map.map(LoadOutcome.loaded) ?? .unreadable
    }

    /// La map d'un asset, sans distinguer l'absence de l'illisible — la forme
    /// qu'attend le builder, qui ignore les deux. Qui veut journaliser les
    /// assets perdus passe par `read`.
    public static func load(asset: String, language: String,
                            from kind: Kind,
                            fileManager: FileManager = .default) -> [String: String]? {
        guard case .loaded(let map) = read(asset: asset, language: language,
                                           from: kind, fileManager: fileManager) else {
            return nil
        }
        return map
    }

    /// La date de modification la plus récente des fichiers sources du
    /// dossier — une màj du jeu rafraîchit le glossaire (spec §5).
    public static func newestSourceDate(of kind: Kind,
                                        fileManager: FileManager = .default) -> Date? {
        let files = (try? fileManager.contentsOfDirectory(
            at: kind.folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.pathExtension == kind.fileExtension }
            .compactMap {
                try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
            }
            .max()
    }

    private static func hasFiles(_ folder: URL, extension fileExtension: String,
                                 fileManager: FileManager) -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: folder.path) else {
            return false
        }
        return contents.contains { ($0 as NSString).pathExtension == fileExtension }
    }
}

/// Le cache du glossaire : Application Support et non Caches (spec §5) —
/// cohérent avec `TranslationBaseline` et `ModErrorHistoryStore` : une
/// référence perdue ne se reconstruit pas. Écriture atomique.
public enum GlossaryStore {

    /// Le fichier JSON du cache : version du format, date de construction,
    /// entrées. Les champs sont séparés pour que `Glossary` reste le type
    /// pur que consomme le matching.
    private struct Cache: Codable {
        let formatVersion: Int
        let builtAt: Date
        let entries: [GlossaryEntry]
    }

    /// Version du contrat de sortie du cache, **relue** au chargement : un
    /// cache d'une autre version se jette et se reconstruit. Passée à 2
    /// quand le builder a changé de rendu (saisons admises, termes rabotés)
    /// — les fichiers du jeu, eux, n'avaient pas bougé, et la date seule
    /// aurait servi l'ancien glossaire indéfiniment.
    private static let formatVersion = 2

    private static func fileURL(language: String, appSupport: URL) -> URL {
        appSupport.appendingPathComponent("Glossary/\(language).json", isDirectory: false)
    }

    /// Le glossaire en cache, `nil` s'il n'existe pas encore.
    public static func load(language: String, appSupport: URL,
                            fileManager: FileManager = .default) -> Glossary? {
        guard let cache = cache(language: language, appSupport: appSupport) else { return nil }
        return Glossary(entries: cache.entries)
    }

    /// La date de construction du cache — l'entrée d'`needsRebuild`.
    public static func builtDate(language: String, appSupport: URL,
                                 fileManager: FileManager = .default) -> Date? {
        cache(language: language, appSupport: appSupport)?.builtAt
    }

    /// Le cache lu et **validé** : une autre version de format est traitée
    /// comme une absence, pas comme un cache utilisable.
    private static func cache(language: String, appSupport: URL) -> Cache? {
        let file = fileURL(language: language, appSupport: appSupport)
        guard let data = try? Data(contentsOf: file),
              let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.formatVersion == formatVersion else { return nil }
        return cache
    }

    /// Écrit le cache de façon atomique (`.tmp` → rename via `Data.write`).
    public static func save(_ glossary: Glossary, language: String, appSupport: URL,
                            fileManager: FileManager = .default) throws {
        let file = fileURL(language: language, appSupport: appSupport)
        try fileManager.createDirectory(at: file.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        let cache = Cache(formatVersion: formatVersion, builtAt: Date(), entries: glossary.entries)
        let data = try JSONEncoder().encode(cache)
        try data.write(to: file, options: .atomic)
    }

    /// `true` quand les sources sont strictement plus récentes que le cache.
    /// À égalité, pas de rebuild : le cache vient d'être écrit sur ces
    /// sources-là.
    public static func needsRebuild(cachedAt: Date, sourcesNewerThan: Date) -> Bool {
        sourcesNewerThan > cachedAt
    }
}
