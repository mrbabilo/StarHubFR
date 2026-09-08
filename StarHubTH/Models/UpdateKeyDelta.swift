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
