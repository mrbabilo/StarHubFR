import Foundation

/// Le catalogue des objets du jeu installé (B4) : nom affiché dans la langue
/// du jeu, planche et case de l'icône, catégorie. Lu dans `Data/Objects` et
/// `Data/BigCraftables` ; un `DisplayName` `[LocalizedText Fichier:Clé]`
/// se résout par `Strings/<Fichier>.<suffixe>.xnb`, puis par le fichier de
/// base, puis par le `Name` interne. Ne sert qu'à l'affichage : jamais écrit
/// dans une partie.
struct GameCatalog: Sendable {
    struct Entry: Equatable, Sendable {
        let id: String
        let displayName: String
        /// `nil` : la planche par défaut du jeu.
        let texture: String?
        let spriteIndex: Int
        let category: Int
    }

    let objects: [String: Entry]
    let bigCraftables: [String: Entry]

    /// Catégorie que le jeu donne aux gros objets (`Object.BigCraftableCategory`).
    static let bigCraftableCategory = -9

    /// L'entrée d'une case : la table `BigCraftables` pour un gros objet (un
    /// Coffre `130` n'est pas le Thon), `Objects` pour un `xsi:type="Object"`,
    /// rien pour le reste (armes, outils : le nom de la partie reste).
    func entry(for item: InventoryItem) -> Entry? {
        if item.isBigCraftable { return bigCraftables[Self.unqualified(item.itemId, "(BC)")] }
        guard item.isObject else { return nil }
        return objects[Self.unqualified(item.itemId, "(O)")]
    }

    private static func unqualified(_ id: String, _ prefix: String) -> String {
        id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
    }

    // MARK: - Chargement

    /// Lit le catalogue dans le dossier `Content` du jeu. `language` : le code
    /// de langue du jeu (`fr`, `de`, `en`…). Fichiers `Data` absents :
    /// `gameNotFound` ; illisibles : `unreadable`. Un fichier `Strings`
    /// manquant ou illisible ne fait que replier le nom.
    static func load(gameContent: URL, language: String) -> Result<GameCatalog, CatalogProblem> {
        func table(_ name: String, _ schema: XnbSchema) -> Result<XnbValue, CatalogProblem> {
            let url = gameContent.appendingPathComponent("Data/\(name).xnb")
            guard let data = FileManager.default.contents(atPath: url.path) else { return .failure(.gameNotFound) }
            do { return .success(try XnbTypedReader.read(data, root: schema)) }
            // Le nom du fichier seulement : la ligne s'affiche telle quelle à l'utilisateur.
            catch { return .failure(.unreadable("Data/\(name).xnb")) }
        }
        let objects: XnbValue, bigCraftables: XnbValue
        switch (table("Objects", .objects), table("BigCraftables", .bigCraftables)) {
        case (.success(let o), .success(let b)): (objects, bigCraftables) = (o, b)
        case (.failure(let problem), _), (_, .failure(let problem)): return .failure(problem)
        }
        var cache: [String: [String: String]?] = [:]
        return .success(build(objects: objects, bigCraftables: bigCraftables, language: language) { asset in
            if let cached = cache[asset] { return cached }
            let url = gameContent.appendingPathComponent(asset + ".xnb")
            let strings = FileManager.default.contents(atPath: url.path).flatMap { data -> [String: String]? in
                do { return try XnbStringDictionaryReader.read(data) } catch { return nil } // repli sur la base
            }
            cache[asset] = strings
            return strings
        })
    }

    /// Le catalogue depuis les deux tables lues ; `strings` rend le
    /// dictionnaire d'un fichier `Strings` (`Strings/Objects.fr-FR`, sans
    /// extension), `nil` s'il manque.
    static func build(objects: XnbValue, bigCraftables: XnbValue, language: String,
                      strings: (String) -> [String: String]?) -> GameCatalog {
        let suffix = fileSuffix(languageCode: language)
        func resolve(_ displayName: String, name: String) -> String {
            guard let (file, key) = localizedTextReference(displayName) else { return displayName.isEmpty ? name : displayName }
            if let suffix, let text = strings("\(file).\(suffix)")?[key] { return text }
            return strings(file)?[key] ?? name
        }
        func entries(_ table: XnbValue, category fixed: Int?) -> [String: Entry] {
            guard case .dictionary(let pairs) = table else { return [:] }
            var result: [String: Entry] = [:]
            for pair in pairs {
                guard case .string(let id) = pair.key, case .object(let fields) = pair.value else { continue }
                let name = fields["Name"]?.stringValue ?? id
                let texture = fields["Texture"]?.stringValue
                result[id] = Entry(id: id,
                                   displayName: resolve(fields["DisplayName"]?.stringValue ?? "", name: name),
                                   texture: texture?.isEmpty == false ? texture : nil,
                                   spriteIndex: fields["SpriteIndex"]?.intValue ?? 0,
                                   category: fixed ?? fields["Category"]?.intValue ?? 0)
            }
            return result
        }
        return GameCatalog(objects: entries(objects, category: nil),
                           bigCraftables: entries(bigCraftables, category: bigCraftableCategory))
    }

    /// `[LocalizedText Strings\\Objects:Parsnip_Name]` → (`Strings/Objects`,
    /// `Parsnip_Name`). Arguments après la clé ignorés ; `nil` pour un texte
    /// littéral.
    static func localizedTextReference(_ text: String) -> (file: String, key: String)? {
        let prefix = "[LocalizedText "
        guard text.hasPrefix(prefix), text.hasSuffix("]") else { return nil }
        let body = text.dropFirst(prefix.count).dropLast()
        guard let reference = body.split(separator: " ").first,
              let colon = reference.firstIndex(of: ":") else { return nil }
        let file = reference[..<colon].replacingOccurrences(of: "\\", with: "/")
        let key = String(reference[reference.index(after: colon)...])
        return file.isEmpty || key.isEmpty ? nil : (file, key)
    }

    // MARK: - Langue et dossier du jeu

    /// Suffixe des fichiers traduits du jeu (`LocalizedContentManager`) ;
    /// `nil` : le fichier de base (`en`, langue de mod, code inconnu).
    static func fileSuffix(languageCode: String) -> String? {
        let suffixes = ["ja": "ja-JP", "ru": "ru-RU", "zh": "zh-CN", "pt": "pt-BR", "es": "es-ES",
                        "de": "de-DE", "th": "th-TH", "fr": "fr-FR", "ko": "ko-KR", "it": "it-IT",
                        "tr": "tr-TR", "hu": "hu-HU"]
        return suffixes[languageCode]
    }

    /// La langue du jeu : `<languageCode>` de `startup_preferences`, sinon
    /// celle de l'app (`fr` → fichiers `fr-FR`).
    static func gameLanguage(startupPreferences: Data?, appLanguage: String) -> String {
        guard let data = startupPreferences, let text = String(data: data, encoding: .utf8),
              let range = text.range(of: "<languageCode>\\s*([^<\\s]+)\\s*</languageCode>", options: .regularExpression)
        else { return appLanguage }
        let tag = text[range]
        return tag.replacingOccurrences(of: "</?languageCode>|\\s", with: "", options: .regularExpression)
    }

    /// Le dossier `Content` depuis `gameDir` (`<app>/Contents/MacOS`),
    /// ou depuis le `.app` lui-même ; `nil` s'il n'existe pas.
    static func contentFolder(gameDir: String) -> URL? {
        guard !gameDir.isEmpty else { return nil }
        let dir = URL(fileURLWithPath: gameDir)
        let candidates = [
            dir.deletingLastPathComponent().appendingPathComponent("Resources/Content"),
            dir.appendingPathComponent("Contents/Resources/Content"),
            dir.appendingPathComponent("Content"),
        ]
        return candidates.first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// Tout le chemin de l'app : dossier du jeu, langue, lecture. Sans fil
    /// imposé — à appeler hors du fil principal.
    static func load(gameDir: String, appLanguage: String,
                     appDataFolder: URL = GameControlPreferences.appDataFolder) -> Result<GameCatalog, CatalogProblem> {
        guard let content = contentFolder(gameDir: gameDir) else { return .failure(.gameNotFound) }
        let prefs = FileManager.default.contents(atPath: appDataFolder.appendingPathComponent("startup_preferences").path)
        return load(gameContent: content, language: gameLanguage(startupPreferences: prefs, appLanguage: appLanguage))
    }
}

/// Pourquoi le catalogue manque : affiché en une ligne au-dessus du sac.
enum CatalogProblem: Error, Equatable, Sendable {
    case gameNotFound
    case unreadable(String)
}

private extension XnbValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .int(let value) = self { return Int(value) }
        return nil
    }
}
