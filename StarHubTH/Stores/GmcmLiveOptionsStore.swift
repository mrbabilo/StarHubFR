import Foundation

/// Les choix d'enum lus **à la volée** dans les DLL du mod (**C4-T11
/// suite**). Le dataset figé (`GmcmOptions.bundled`, relevé du parc) ne
/// couvre ni un mod installé après lui, ni une mise à jour qui ajoute des
/// options — l'analyse locale ferme les deux trous : à l'ouverture de
/// l'éditeur, chaque DLL du mod est relue via `DotNetAssemblyOptions`, et
/// le résultat est mis en cache.
///
/// Le cache vit dans `AppSupport/StarHubFR/DllOptions/<uid>.json`, validé
/// par l'empreinte (mtime + taille) de chaque DLL : une mise à jour change
/// l'empreinte, l'entrée se recalcule à l'ouverture suivante. Coût d'une
/// analyse : les seules tables de métadonnées, quelques millisecondes.
///
/// Hors de l'application (suite de tests), `AppSupport.directory` ne crée
/// rien et le cache est simplement court-circuité.
///
/// Les `try?` de ce fichier sont délibérés et assumés au cliquet : ils ne
/// portent que la mécanique de cache, où absence et corruption signifient
/// « recalculer » — un comportement correct et observable, pas une cause
/// d'échec à remonter. Aucune lecture de **donnée** n'en dépend : une DLL
/// illisible rend `nil`, et l'appelant retombe sur le dataset figé.
enum GmcmLiveOptionsStore {

    private struct CacheEntry: Codable {
        var files: [String: String]
        var options: [String: [String]]
    }

    /// Les choix du mod, live. `nil` quand aucune DLL n'a pu se lire —
    /// l'appelant retombe alors sur le dataset figé.
    static func choices(modFolder: URL, uniqueId: String) -> [String: [String]]? {
        let fm = FileManager.default
        let dllNames = (try? fm.contentsOfDirectory(atPath: modFolder.path))?
            .filter { $0.hasSuffix(".dll") }
            .sorted() ?? []
        guard !dllNames.isEmpty else { return nil }

        var footprint: [String: String] = [:]
        for name in dllNames {
            let url = modFolder.appendingPathComponent(name)
            guard let attributes = try? fm.attributesOfItem(atPath: url.path),
                  let modified = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? Int else { return nil }
            footprint[name] = "\(modified.timeIntervalSince1970).\(size)"
        }

        let cacheURL: URL? = {
            guard let directory = AppSupport.directory else { return nil }
            return directory.appendingPathComponent("DllOptions", isDirectory: true)
                .appendingPathComponent(cacheFileName(uniqueId))
        }()
        if let cacheURL, let entry = readCache(at: cacheURL), entry.files == footprint {
            return entry.options
        }

        // Le filtre de pertinence, côté app : une propriété n'est un choix
        // de config que si SA CLÉ existe dans le config.json du mod. Sans
        // lui, les enums internes des libs embarquées entrent dans les
        // propositions (mesuré : AccordSettings, deux DLL et zéro clé de
        // config parmi leurs propriétés). Même règle que l'outil.
        var configKeys: Set<String> = []
        if let configData = fm.contents(atPath: modFolder.appendingPathComponent("config.json").path),
           let text = String(data: configData, encoding: .utf8),
           let tree = ConfigJSONTree.parse(text) {
            for leaf in ConfigEditorModel.leaves(of: tree) {
                if let last = leaf.keyPath.last { configKeys.insert(last.lowercased()) }
            }
        }

        // Plusieurs DLL peuvent définir des propriétés de même nom : celle
        // dont les clés recoupent le plus le config gagne les clés
        // disputées — puis le filtre tranche.
        var extracts: [(overlap: Int, options: [String: [String]])] = []
        for name in dllNames {
            guard let data = fm.contents(atPath: modFolder.appendingPathComponent(name).path),
                  let parsed = DotNetAssemblyOptions.extract(assembly: [UInt8](data)) else { continue }
            let overlap = parsed.keys.filter { configKeys.contains($0.lowercased()) }.count
            extracts.append((overlap, parsed))
        }
        extracts.sort { $0.overlap > $1.overlap }
        var options: [String: [String]] = [:]
        for extract in extracts {
            for (key, values) in extract.options where configKeys.contains(key.lowercased()) {
                setdefault(&options, key, values)
            }
        }
        guard !options.isEmpty else { return nil }

        if let cacheURL {
            let entry = CacheEntry(files: footprint, options: options)
            if let data = try? JSONEncoder().encode(entry) {
                try? fm.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
                try? data.write(to: cacheURL, options: .atomic)
            }
        }
        return options
    }

    /// `setdefault` de Python n'a pas d'équivalent Swift : le premier qui
    /// pose une clé gagne (l'ordre d'insertion porte l'arbitrage).
    private static func setdefault(_ dictionary: inout [String: [String]],
                                   _ key: String, _ value: [String]) {
        if dictionary[key] == nil { dictionary[key] = value }
    }

    private static func readCache(at url: URL) -> CacheEntry? {
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else { return nil }
        return entry
    }

    /// Un UniqueID en nom de fichier : il peut porter des caractères que le
    /// système refuse ; le hacher suffit, le contenu porte déjà l'empreinte.
    private static func cacheFileName(_ uniqueId: String) -> String {
        String(format: "%016llx", stableHash(uniqueId.lowercased())) + ".json"
    }

    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
