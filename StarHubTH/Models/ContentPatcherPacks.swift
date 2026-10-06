import Foundation

/// D2-T3 §3.1 — le poids Content Patcher d'un pack : patches déclarés
/// (`Changes` + `DynamicChanges`) et inclusions suivies (`Include`), lus
/// dans `content.json`. Tolérant : JSON cassé = `illisible`, jamais un
/// total inventé.
public struct ContentPatcherPackCount: Equatable, Sendable {
    public enum State: Equatable, Sendable { case ok, illisible }
    public let packName: String
    public let patches: Int
    public let includesRead: Int
    public let state: State
}

public enum ContentPatcherPacks {

    /// Un mod racine et ses packs CP (« SVE = [CP] + [FTM] », spec §3.1).
    public struct Group: Equatable, Sendable {
        public let rootName: String
        public let packs: [ContentPatcherPackCount]
        /// Les packs illisibles ne comptent pas : le total reste un plancher vrai.
        public var totalPatches: Int {
            packs.reduce(0) { $0 + ($1.state == .ok ? $1.patches : 0) }
        }
    }

    public static let maxIncludeDepth = 5

    /// Compte les patches d'un `content.json`. `includeLoader` rend le texte
    /// du fichier inclus pour un chemin relatif à la racine du pack, ou `nil`
    /// s'il n'existe pas (inclusion manquante : SMAPI le signalera lui-même).
    public static func count(packName: String, contentJSON: String,
                             includeLoader: (String) -> String?) -> ContentPatcherPackCount {
        guard let obj = Self.jsonObject(contentJSON) else {
            return ContentPatcherPackCount(packName: packName, patches: 0, includesRead: 0, state: .illisible)
        }
        var visited: Set<String> = []
        var includesRead = 0
        let patches = Self.countPatches(obj: obj, dir: "", depth: 0,
                                        includeLoader: includeLoader,
                                        visited: &visited, includesRead: &includesRead)
        return ContentPatcherPackCount(packName: packName, patches: patches,
                                       includesRead: includesRead, state: .ok)
    }

    private static func countPatches(obj: [String: Any], dir: String, depth: Int,
                                     includeLoader: (String) -> String?,
                                     visited: inout Set<String>, includesRead: inout Int) -> Int {
        var total = (obj["Changes"] as? [Any] ?? []).count
        total += (obj["DynamicChanges"] as? [Any] ?? []).count
        guard depth < maxIncludeDepth else { return total }
        for path in includePaths(obj["Include"]) {
            let relative = dir.isEmpty ? path : dir + "/" + path
            guard !visited.contains(relative),
                  let text = includeLoader(relative),
                  let child = jsonObject(text) else { continue }
            visited.insert(relative)
            includesRead += 1
            total += countPatches(obj: child, dir: (relative as NSString).deletingLastPathComponent,
                                  depth: depth + 1, includeLoader: includeLoader,
                                  visited: &visited, includesRead: &includesRead)
        }
        return total
    }

    /// CP parse avec Newtonsoft : commentaires, virgules traînantes, clés nues
    /// et contrôles bruts sont légaux. Réutiliser le parseur commun évite une
    /// seconde implémentation incomplète — notamment le piège Swift où `\r\n`
    /// forme un seul `Character` et fait avaler la fin d'un fichier commenté.
    private static func jsonObject(_ text: String) -> [String: Any]? {
        I18nLenientParser.lenientObject(text)
    }

    /// `Include` est un tableau de chemins ; un stub de pack peut écrire une
    /// chaîne seule — les deux formes passent.
    private static func includePaths(_ value: Any?) -> [String] {
        if let list = value as? [String] { return list }
        if let one = value as? String { return [one] }
        return []
    }
}
