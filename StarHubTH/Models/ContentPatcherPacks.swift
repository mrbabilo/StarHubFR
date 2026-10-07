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
    /// Cibles `Load` **certaines** du pack (A5-T4), Include suivis : sans
    /// `When`, sans `Priority` déclarée (le défaut CP est `Exclusive` — deux
    /// exclusifs sur une cible, **aucun des deux ne s'applique**), sans jeton
    /// `{{…}}` dans `Target` ; cibles multiples `,`/`|` éclatées, casse pliée.
    public let loadTargets: Set<String>
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

    /// Un dossier de pack CP d'une racine : le nom affiché, le `folderName`
    /// **logique** (`Racine/Composant` pour un composant) et le chemin réel.
    public struct PackDirectory: Equatable, Sendable {
        public let name: String
        public let folderName: String
        public let path: String
    }

    /// Les dossiers portant un `content.json` sous `root` : la racine
    /// elle-même, puis ses composants. Le point de pause vit sur l'entrée de
    /// tête (`physicalFolderName`) ; les composants viennent du groupe déjà
    /// constitué par la découverte — pas de second balayage du disque.
    public static func packDirectories(of root: ModItem, modsRoot: String) -> [PackDirectory] {
        let fm = FileManager.default
        let rootPhysical = (modsRoot as NSString).appendingPathComponent(root.physicalFolderName)
        var dirs: [PackDirectory] = []
        if fm.fileExists(atPath: rootPhysical + "/content.json") {
            dirs.append(PackDirectory(name: root.name, folderName: root.folderName, path: rootPhysical))
        }
        for comp in root.components {
            guard let slash = comp.folderName.firstIndex(of: "/") else { continue }
            let dir = rootPhysical + "/" + comp.folderName[comp.folderName.index(after: slash)...]
            if fm.fileExists(atPath: dir + "/content.json") {
                dirs.append(PackDirectory(name: comp.name, folderName: comp.folderName, path: dir))
            }
        }
        return dirs
    }

    /// Lit et compte un pack sur le disque ; `content.json` illisible =
    /// `illisible`, jamais un total inventé.
    public static func read(_ dir: PackDirectory) -> ContentPatcherPackCount {
        let url = URL(fileURLWithPath: dir.path)
        guard let text = try? String(contentsOf: url.appendingPathComponent("content.json"), encoding: .utf8) else {
            return ContentPatcherPackCount(packName: dir.name, patches: 0, includesRead: 0,
                                           includesUnread: 0, loadTargets: [], state: .illisible)
        }
        return count(packName: dir.name, contentJSON: text) { rel in
            try? String(contentsOf: url.appendingPathComponent(rel), encoding: .utf8)
        }
    }

    /// Compte les patches d'un `content.json`. `includeLoader` rend le texte
    /// du fichier inclus pour un chemin relatif à la racine du pack, ou `nil`
    /// s'il n'existe pas (inclusion manquante : souvent conditionnelle à un
    /// mod absent, et SMAPI la signale lui-même — ni lue, ni non lue).
    public static func count(packName: String, contentJSON: String,
                             includeLoader: (String) -> String?) -> ContentPatcherPackCount {
        guard let obj = Self.jsonObject(contentJSON) else {
            return ContentPatcherPackCount(packName: packName, patches: 0, includesRead: 0,
                                           includesUnread: 0, loadTargets: [], state: .illisible)
        }
        // Le parcours ne garde pas le loader au-delà de cet appel.
        return withoutActuallyEscaping(includeLoader) { loader in
            var walk = Walk(includeLoader: loader)
            let patches = walk.countPatches(obj: obj, depth: 0)
            return ContentPatcherPackCount(packName: packName, patches: patches,
                                           includesRead: walk.includesRead,
                                           includesUnread: walk.includesUnread,
                                           loadTargets: walk.loadTargets, state: .ok)
        }
    }

    private struct Walk {
        let includeLoader: (String) -> String?
        /// Clés en minuscules : le disque du parc est insensible à la casse
        /// et SVE écrit `code/items/…` comme `code/Items/…`.
        var visited: Set<String> = []
        var includesRead = 0
        var includesUnread = 0
        var loadTargets: Set<String> = []

        /// `conditional` : un ancêtre `Include` porte un `When` — tout ce qu'il
        /// charge est alors conditionnel, et aucune cible n'y est certaine
        /// (les « Seasonal Include » de SVE en sont l'exemple du parc).
        mutating func countPatches(obj: [String: Any], depth: Int, conditional: Bool = false) -> Int {
            var total = 0
            for patch in ContentPatcherPacks.field(obj, "Changes") as? [Any] ?? [] {
                guard let dict = patch as? [String: Any],
                      let action = ContentPatcherPacks.field(dict, "Action") as? String,
                      action.caseInsensitiveCompare("Include") == .orderedSame else {
                    total += 1
                    if !conditional, let dict = patch as? [String: Any],
                       let targets = ContentPatcherPatches.certainLoadTargets(of: dict) {
                        loadTargets.formUnion(targets)
                    }
                    continue
                }
                let childConditional = conditional || ContentPatcherPacks.field(dict, "When") != nil
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
                    total += countPatches(obj: child, depth: depth + 1, conditional: childConditional)
                }
            }
            return total
        }
    }

    /// Newtonsoft désérialise les modèles CP sans tenir compte de la casse
    /// des clés : 193 `action` et 2 `changes` en minuscules dans le parc.
    static func field(_ obj: [String: Any], _ name: String) -> Any? {
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
