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

    /// BOM UTF-8 toléré (certains packs Windows l'embarquent). CP parse le
    /// content.json avec Newtonsoft : commentaires `//` et `/*…*/` (et
    /// virgules traînantes) y sont légaux — 24 des 137 content.json du vrai
    /// parc (2026-10-06) en portent, dont SVE et Ridgeside. `JSONSerialization`
    /// est strict : nettoyage d'abord, en respectant les chaînes (une URL ou
    /// un texte peut contenir `//`, `,}` ou `/*`).
    private static func jsonObject(_ text: String) -> [String: Any]? {
        let cleaned = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        guard let data = lenient(cleaned).data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return obj
    }

    /// Retire les commentaires `//…` et `/*…*/` et les virgules traînantes
    /// hors chaînes. Une seule passe, O(n).
    private static func lenient(_ text: String) -> String {
        var chars = Array(text)
        var out: [Character] = []
        out.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {                          // chaîne : copiée telle quelle
                out.append(c); i += 1
                while i < chars.count {
                    out.append(chars[i])
                    if chars[i] == "\\", i + 1 < chars.count {
                        out.append(chars[i + 1]); i += 2; continue
                    }
                    let closed = chars[i] == "\""
                    i += 1
                    if closed { break }
                }
            } else if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                i += 2
                while i < chars.count, chars[i] != "\n" { i += 1 }
            } else if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(i + 2, chars.count)
            } else if c == "," {
                var j = i + 1
                while j < chars.count,
                      chars[j] == " " || chars[j] == "\t" || chars[j] == "\n" || chars[j] == "\r" { j += 1 }
                if j < chars.count, chars[j] == "}" || chars[j] == "]" {
                    i += 1                          // virgule traînante : retirée
                } else {
                    out.append(c); i += 1
                }
            } else {
                out.append(c); i += 1
            }
        }
        return String(out)
    }

    /// `Include` est un tableau de chemins ; un stub de pack peut écrire une
    /// chaîne seule — les deux formes passent.
    private static func includePaths(_ value: Any?) -> [String] {
        if let list = value as? [String] { return list }
        if let one = value as? String { return [one] }
        return []
    }
}
