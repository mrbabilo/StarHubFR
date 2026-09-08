import Foundation

/// Les ensembles de clés d'un dossier de mod, à un instant donné — l'ancien
/// sur disque ou la source extraite dans le tempDir. C2-T4 §3.1.
public struct UpdateKeySnapshot: Equatable, Sendable {
    /// Clé → valeur du `config.json` racine. `nil` = pas de `config.json`
    /// livré : l'absence et la vacuité ne se confondent pas, la comparaison
    /// en dépend. Les valeurs servent au delta (§3.2) et au report.
    public let config: [String: String]?
    /// Les clés de premier niveau, dérivées — commodité de comparaison.
    public var configKeys: Set<String>? { config.map { Set($0.keys) } }
    /// Composant (`""` pour un mod simple) → (clé → valeur EN) du fichier
    /// anglais de référence (`i18n/default.json`, sinon `i18n/en.json` —
    /// même règle que C1-T1).
    public let english: [String: [String: String]]
    /// Composant → (clé → valeur FR) de `i18n/fr.json`.
    public let french: [String: [String: String]]

    public init(config: [String: String]?,
                english: [String: [String: String]],
                french: [String: [String: String]]) {
        self.config = config
        self.english = english
        self.french = french
    }

    /// Lecture synchrone, à appeler hors du fil principal (le parsing d'un
    /// gros pack est celui de `TranslationCoverage` : millisecondes).
    public static func read(folder: URL) -> UpdateKeySnapshot {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else {
            return UpdateKeySnapshot(config: nil, english: [:], french: [:])
        }

        // config.json racine — clés et valeurs de premier niveau.
        let configURL = folder.appendingPathComponent("config.json")
        var config: [String: String]? = nil
        if let data = try? Data(contentsOf: configURL) {
            config = stringValues(of: data)
        }

        var english: [String: [String: String]] = [:]
        var french: [String: [String: String]] = [:]

        // Racine + composants : un composant est un sous-dossier portant un
        // manifeste — même convention que la traversée de `TranslationCoverage`.
        var components: [(name: String, dir: URL)] = [("", folder)]
        if let entries = try? fm.contentsOfDirectory(atPath: folder.path) {
            for entry in entries.sorted() where !entry.hasPrefix(".") {
                let sub = folder.appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: sub.path, isDirectory: &isDir),
                      isDir.boolValue,
                      fm.fileExists(atPath: sub.appendingPathComponent("manifest.json").path)
                else { continue }
                components.append((entry, sub))
            }
        }

        for (name, dir) in components {
            let i18n = dir.appendingPathComponent("i18n")
            if let values = languageValues(at: i18n, file: "default.json")
                ?? languageValues(at: i18n, file: "en.json") {
                english[name] = values
            }
            if let values = languageValues(at: i18n, file: "fr.json") {
                french[name] = values
            }
        }

        return UpdateKeySnapshot(config: config, english: english, french: french)
    }

    /// Clés → valeurs chaîne d'un JSON d'objet (les valeurs non-chaîne du
    /// config.json passent en forme texte : seules les clés de premier niveau
    /// comptent ici, le report config traite les valeurs via
    /// `RenameReport.applyToConfig`). Tolère le BOM ; nil si le fichier n'est
    /// pas un objet JSON lisible.
    private static func stringValues(of data: Data) -> [String: String]? {
        guard let text = decodeText(data),
              let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return nil }
        return obj.mapValues(scalarString)
    }

    /// Forme texte d'un scalaire JSON. Un booléen passe par `NSNumber` :
    /// l'interpolation `"\(…)"` rendrait « 1 »/« 0 » — le jeu écrit
    /// `true`/`false`, et c'est cette forme que l'utilisateur reconnaît.
    private static func scalarString(_ value: Any) -> String {
        switch value {
        case let s as String:
            return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        default:
            return "\(value)"
        }
    }

    /// Clés → valeurs d'un fichier i18n, par `I18nFileDecoder` (UTF-16/32
    /// réels sur le parc — jamais `String(data:encoding:.utf8)` direct).
    private static func languageValues(at i18n: URL, file: String) -> [String: String]? {
        let url = i18n.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url),
              let decoded = I18nFileDecoder.decode(data),
              let obj = try? JSONSerialization.jsonObject(with: Data(decoded.text.utf8)) as? [String: Any]
        else { return nil }
        return obj.mapValues(scalarString)
    }

    /// Décodage texte tolérant : I18nFileDecoder d'abord, UTF-8 en repli.
    private static func decodeText(_ data: Data) -> String? {
        I18nFileDecoder.decode(data)?.text ?? String(data: data, encoding: .utf8)
    }
}

// MARK: - Le delta (C2-T4 §3.2)

/// Une clé ancienne et sa remplaçante présumée — le pairage des renommages
/// (`KeyRenameMatcher`) produit ces paires, le report les applique.
public struct RenamePair: Codable, Equatable, Hashable, Sendable {
    public let oldKey: String
    public let newKey: String

    public init(oldKey: String, newKey: String) {
        self.oldKey = oldKey
        self.newKey = newKey
    }
}

/// Le delta des clés de premier niveau du `config.json`. Les valeurs
/// embarquées : `added` porte celle du neuf, `removed` celle de
/// l'utilisateur au moment de la capture — ce qu'un report voudrait
/// ré-poser, et ce qu'une ligne d'écran sait montrer.
public struct KeySetDelta: Codable, Equatable, Hashable, Sendable {
    public var added: [String: String]
    public var removed: [String: String]
    /// Les paires déjà réconciliées par un report — ni re-proposées, ni
    /// comptées deux fois.
    public var reconciled: [RenamePair]

    public init(added: [String: String], removed: [String: String],
                reconciled: [RenamePair]) {
        self.added = added
        self.removed = removed
        self.reconciled = reconciled
    }
}

/// Le delta des clés de traduction. `addedUntranslated` : les textes neufs
/// à traduire ; `addedAuthorTranslated` : traduits par l'auteur dans son
/// propre `fr.json`, écartés par la préservation mais jamais perdus de vue ;
/// `removedKeys` : disparus du neuf, avec leur valeur ancienne.
public struct TranslationKeyDelta: Codable, Equatable, Hashable, Sendable {
    public var addedUntranslated: [String: String]
    public var addedAuthorTranslated: [String: String]
    public var removedKeys: [String: String]
    public var reconciled: [RenamePair]

    public init(addedUntranslated: [String: String],
                addedAuthorTranslated: [String: String],
                removedKeys: [String: String],
                reconciled: [RenamePair]) {
        self.addedUntranslated = addedUntranslated
        self.addedAuthorTranslated = addedAuthorTranslated
        self.removedKeys = removedKeys
        self.reconciled = reconciled
    }
}

/// Ce qu'une mise à jour a changé aux clés d'un mod — capturé à
/// l'installation (§5), persisté par `UniqueID` (§6), affiché sur la fiche
/// (§7.2) et réconciliable (§8).
public struct ModUpdateKeyDelta: Codable, Equatable, Hashable, Sendable {
    public let uniqueId: String
    public let folderName: String
    public let date: Date
    public let config: KeySetDelta?
    public let translation: TranslationKeyDelta

    public init(uniqueId: String, folderName: String, date: Date,
                config: KeySetDelta?, translation: TranslationKeyDelta) {
        self.uniqueId = uniqueId
        self.folderName = folderName
        self.date = date
        self.config = config
        self.translation = translation
    }

    public var isEmpty: Bool {
        let configEmpty = config.map {
            $0.added.isEmpty && $0.removed.isEmpty && $0.reconciled.isEmpty
        } ?? true
        let translationEmpty = translation.addedUntranslated.isEmpty
            && translation.addedAuthorTranslated.isEmpty
            && translation.removedKeys.isEmpty
            && translation.reconciled.isEmpty
        return configEmpty && translationEmpty
    }

    /// Compare l'ancien et le neuf. Rend `nil` quand rien n'a bougé : pas de
    /// ligne à l'écran, pas de fichier dans le store.
    public static func compare(old: UpdateKeySnapshot, new: UpdateKeySnapshot,
                               uniqueId: String, folderName: String,
                               now: Date = Date()) -> ModUpdateKeyDelta? {
        // Config : l'archive sans config.json se tait — l'absence n'est pas
        // « zéro option retirée ».
        let configDelta: KeySetDelta?
        if let newConfig = new.config {
            let oldConfig = old.config ?? [:]
            configDelta = KeySetDelta(
                added: newConfig.filter { oldConfig[$0.key] == nil },
                removed: oldConfig.filter { newConfig[$0.key] == nil },
                reconciled: [])
        } else {
            configDelta = nil
        }

        // Traduction, par composant ; les clés sont qualifiées
        // `Composant/clé` dès qu'un composant entre en jeu.
        var addedUntranslated: [String: String] = [:]
        var addedAuthorTranslated: [String: String] = [:]
        var removedKeys: [String: String] = [:]

        for (component, newKeys) in new.english {
            let oldKeys = old.english[component] ?? [:]
            let prefix = component.isEmpty ? "" : "\(component)/"
            for (key, value) in newKeys where oldKeys[key] == nil {
                let qualified = prefix + key
                if let authorFR = new.french[component]?[key] {
                    addedAuthorTranslated[qualified] = authorFR
                } else {
                    addedUntranslated[qualified] = value
                }
            }
            for (key, value) in oldKeys where newKeys[key] == nil {
                removedKeys[prefix + key] = value
            }
        }
        // Les composants disparus entiers versent leurs clés dans removedKeys.
        for (component, oldKeys) in old.english where new.english[component] == nil {
            let prefix = component.isEmpty ? "" : "\(component)/"
            for (key, value) in oldKeys { removedKeys[prefix + key] = value }
        }

        let delta = ModUpdateKeyDelta(
            uniqueId: uniqueId, folderName: folderName, date: now,
            config: configDelta,
            translation: TranslationKeyDelta(
                addedUntranslated: addedUntranslated,
                addedAuthorTranslated: addedAuthorTranslated,
                removedKeys: removedKeys, reconciled: []))
        return delta.isEmpty ? nil : delta
    }
}
