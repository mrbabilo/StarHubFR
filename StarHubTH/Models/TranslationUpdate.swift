import Foundation

/// Une mise à jour qui apporte **son** `fr.json` alors qu'une traduction
/// locale existe (demande de l'auteur, 2026-10-03). Jusque-là la
/// préservation gardait toujours la locale, en silence : la traduction de
/// l'auteur, parfois plus complète, se perdait sans qu'on le sache.
///
/// L'aperçu montre la comparaison et propose trois gestes (`Choice`) ; le
/// fichier écarté n'est jamais perdu — la locale vit dans la sauvegarde
/// d'avant mise à jour, celle de l'auteur est mise à l'abri ici.
public enum TranslationUpdate {

    public enum Choice: Hashable, Sendable {
        /// Le comportement d'avant : la traduction locale reste.
        case keepLocal
        case takeAuthor
        /// Les lignes locales restent ; celles de l'auteur entrent pour les
        /// clés que la locale n'a pas.
        case merge
    }

    public struct Comparison: Equatable, Sendable {
        public let localKeys: Int
        public let authorKeys: Int
        /// Clés des deux côtés, valeurs différentes.
        public let differing: Int
        /// Clés que seul l'auteur traduit.
        public let authorOnly: Int
        /// Clés que seule la locale porte.
        public let localOnly: Int

        public var isIdentical: Bool { differing == 0 && authorOnly == 0 && localOnly == 0 }

        public static func compare(local: [String: String], author: [String: String]) -> Comparison {
            Comparison(localKeys: local.count, authorKeys: author.count,
                       differing: author.filter { key, value in local[key].map { $0 != value } ?? false }.count,
                       authorOnly: author.keys.filter { local[$0] == nil }.count,
                       localOnly: local.keys.filter { author[$0] == nil }.count)
        }
    }

    /// Où mettre à l'abri le `fr.json` de l'auteur écarté par `keepLocal` :
    /// à côté des sauvegardes d'installation (`backups` du gestionnaire
    /// injecté — un test n'écrit jamais dans le vrai Application Support).
    public static func discardedRoot(backupsDirectory: URL, folderName: String, stamp: String) -> URL {
        backupsDirectory.deletingLastPathComponent()
            .appendingPathComponent("TranslationsDiscarded/\(stamp)", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// Les `fr.json` présents **des deux côtés** (chemins relatifs au dossier
    /// du mod, composants compris), et leur comparaison quand ils diffèrent.
    public static func comparisons(source: URL, installed: URL) -> [String: Comparison] {
        var out: [String: Comparison] = [:]
        for relative in frenchFiles(under: source) {
            guard let author = entries(source.appendingPathComponent(relative)),
                  let local = entries(installed.appendingPathComponent(relative)) else { continue }
            let comparison = Comparison.compare(local: local, author: author)
            if !comparison.isIdentical { out[relative] = comparison }
        }
        return out
    }

    /// Applique le choix, **après** la restauration habituelle (qui a remis
    /// la locale en place) : `destination` porte alors la locale, `source`
    /// l'auteur. Le fichier écarté par `keepLocal` est copié sous
    /// `discardedRoot` ; la locale remplacée vit dans la sauvegarde d'avant
    /// mise à jour.
    public static func apply(_ choice: Choice, relativePaths: [String], source: URL, destination: URL,
                             discardedRoot: URL?) throws {
        let fm = FileManager.default
        for relative in relativePaths {
            let author = source.appendingPathComponent(relative)
            let local = destination.appendingPathComponent(relative)
            guard fm.fileExists(atPath: author.path), fm.fileExists(atPath: local.path) else { continue }
            switch choice {
            case .keepLocal:
                guard let root = discardedRoot else { continue }
                let copy = root.appendingPathComponent(relative)
                try fm.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: copy.path) { try fm.removeItem(at: copy) }
                try fm.copyItem(at: author, to: copy)
            case .takeAuthor:
                try fm.removeItem(at: local)
                try fm.copyItem(at: author, to: local)
            case .merge:
                guard let localData = fm.contents(atPath: local.path),
                      let localText = I18nFileDecoder.decode(localData)?.text,
                      let localEntries = entries(text: localText),
                      let authorEntries = entries(author),
                      let merged = merged(localText: localText, local: localEntries, author: authorEntries)
                else { continue }
                try Data(merged.utf8).write(to: local, options: .atomic)
            }
        }
    }

    /// Le texte local, ses lignes intactes (commentaires, ordre), les clés
    /// manquantes de l'auteur insérées juste après l'accolade ouvrante — la
    /// virgule finale qu'elles laissent sur un fichier vide est tolérée par
    /// SMAPI (Newtonsoft). `nil` sans accolade trouvée.
    static func merged(localText: String, local: [String: String], author: [String: String]) -> String? {
        let missing = author.filter { local[$0.key] == nil }.sorted { $0.key < $1.key }
        guard !missing.isEmpty else { return localText }
        guard let brace = openingBrace(in: localText) else { return nil }
        let lines = missing.map { "\n  \(jsonString($0.key)): \(jsonString($0.value))," }.joined()
        var text = localText
        text.insert(contentsOf: lines, at: text.index(after: brace))
        return text
    }

    /// La première `{` hors commentaire et hors chaîne.
    static func openingBrace(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            let rest = text[index...]
            if rest.hasPrefix("//") {
                index = rest.firstIndex(where: \.isNewline) ?? text.endIndex
            } else if rest.hasPrefix("/*") {
                index = rest.range(of: "*/").map(\.upperBound) ?? text.endIndex
            } else if text[index] == "{" {
                return index
            } else {
                index = text.index(after: index)
            }
        }
        return nil
    }

    /// Une chaîne JSON échappée, guillemets compris.
    static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// Les entrées d'un i18n ; `nil` s'il est illisible — on ne compare ni ne
    /// fusionne un fichier qu'on ne sait pas lire.
    static func entries(_ url: URL) -> [String: String]? {
        guard let data = FileManager.default.contents(atPath: url.path),
              let text = I18nFileDecoder.decode(data)?.text else { return nil }
        return entries(text: text)
    }

    static func entries(text: String) -> [String: String]? {
        do { return try I18nLenientParser.parse(text) } catch { return nil }
    }

    static func frenchFiles(under folder: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        let base = folder.resolvingSymlinksInPath().path
        var out: [String] = []
        for case let url as URL in enumerator where url.lastPathComponent.lowercased() == "fr.json"
            && url.deletingLastPathComponent().lastPathComponent.lowercased() == "i18n" {
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(base + "/") else { continue }
            out.append(String(path.dropFirst(base.count + 1)))
        }
        return out.sorted()
    }
}
