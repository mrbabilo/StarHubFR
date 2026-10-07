import Foundation

/// D2-T3 §3.1 — le poids Content Patcher d'un pack : patches déclarés dans
/// `Changes`, inclusions comprises. Une inclusion est elle-même un patch
/// (`"Action": "Include"`) : elle est remplacée par les patches du fichier
/// qu'elle charge. Conditions `When` ignorées — on compte ce qui est déclaré,
/// pas ce qui s'applique. Tolérant : JSON cassé = `illisible`, jamais un
/// total inventé.
public struct ContentPatcherPackCount: Equatable, Sendable {
    public enum State: Equatable, Sendable { case ok, illisible }
    public let packName: String
    public let patches: Int
    public let includesRead: Int
    /// Inclusions présentes mais non comptées : chemin à jeton (`{{…}}`,
    /// résolu seulement en jeu) ou fichier illisible. Le total reste un
    /// plancher ; ce compte dit de combien il peut manquer.
    public let includesUnread: Int
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
    /// s'il n'existe pas (inclusion manquante : souvent conditionnelle à un
    /// mod absent, et SMAPI la signale lui-même — ni lue, ni non lue).
    public static func count(packName: String, contentJSON: String,
                             includeLoader: (String) -> String?) -> ContentPatcherPackCount {
        guard let obj = Self.jsonObject(contentJSON) else {
            return ContentPatcherPackCount(packName: packName, patches: 0, includesRead: 0,
                                           includesUnread: 0, state: .illisible)
        }
        // Le parcours ne garde pas le loader au-delà de cet appel.
        return withoutActuallyEscaping(includeLoader) { loader in
            var walk = Walk(includeLoader: loader)
            let patches = walk.countPatches(obj: obj, depth: 0)
            return ContentPatcherPackCount(packName: packName, patches: patches,
                                           includesRead: walk.includesRead,
                                           includesUnread: walk.includesUnread, state: .ok)
        }
    }

    private struct Walk {
        let includeLoader: (String) -> String?
        /// Clés en minuscules : le disque du parc est insensible à la casse
        /// et SVE écrit `code/items/…` comme `code/Items/…`.
        var visited: Set<String> = []
        var includesRead = 0
        var includesUnread = 0

        mutating func countPatches(obj: [String: Any], depth: Int) -> Int {
            var total = 0
            for patch in ContentPatcherPacks.field(obj, "Changes") as? [Any] ?? [] {
                guard let dict = patch as? [String: Any],
                      let action = ContentPatcherPacks.field(dict, "Action") as? String,
                      action.caseInsensitiveCompare("Include") == .orderedSame else {
                    total += 1
                    continue
                }
                guard depth < ContentPatcherPacks.maxIncludeDepth else { continue }
                let fromFile = ContentPatcherPacks.field(dict, "FromFile") as? String ?? ""
                for path in fromFile.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
                where !path.isEmpty {
                    if path.contains("{{") { includesUnread += 1; continue }
                    let key = path.lowercased()
                    guard !visited.contains(key), let text = includeLoader(path) else { continue }
                    visited.insert(key)
                    guard let child = ContentPatcherPacks.jsonObject(text) else {
                        includesUnread += 1
                        continue
                    }
                    includesRead += 1
                    total += countPatches(obj: child, depth: depth + 1)
                }
            }
            return total
        }
    }

    /// Newtonsoft désérialise les modèles CP sans tenir compte de la casse
    /// des clés : 193 `action` et 2 `changes` en minuscules dans le parc.
    private static func field(_ obj: [String: Any], _ name: String) -> Any? {
        if let exact = obj[name] { return exact }
        return obj.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// CP parse avec Newtonsoft : commentaires, virgules traînantes, clés nues
    /// et contrôles bruts sont légaux. Réutiliser le parseur commun évite une
    /// seconde implémentation incomplète — notamment le piège Swift où `\r\n`
    /// forme un seul `Character` et fait avaler la fin d'un fichier commenté.
    private static func jsonObject(_ text: String) -> [String: Any]? {
        I18nLenientParser.lenientObject(text)
    }
}
