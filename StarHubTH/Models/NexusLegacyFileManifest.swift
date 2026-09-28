import Foundation

/// A1-T11 plan 2 — le manifeste d'un fichier Nexus **au format ancien** :
/// `file-metadata.nexusmods.com/file/nexus-files-s3-meta/1303/<modId>/<uri encodée>.json`,
/// un arbre `{children: [{path, name, type, size}]}`. **Chemins seuls** : les
/// tailles sont arrondies (`578.6 kB`, unité non prouvée), aucune empreinte.
///
/// Il ne prouve donc jamais qu'un fichier du disque est celui de l'auteur :
/// il sert de référence de la version installée (chemins) et désigne des
/// fantômes **probables**, jamais cochés d'office. Mesuré le 2026-09-28 : 58 %
/// des mods Nexus du parc n'ont que ce format pour leur version installée.
public struct NexusLegacyFileManifest: Equatable, Sendable {
    /// Chemins de fichiers **relatifs à l'archive** (`ItemBags/ItemBags.dll`).
    public let paths: [String]

    public init(paths: [String]) {
        self.paths = paths
    }

    private struct Node: Decodable {
        let path: String?
        let type: String?
        let children: [Node]?
    }

    /// `nil` quand ce n'est pas un arbre de fichiers : le corps JSON d'un 404
    /// (`{code, message, status}`), une page HTML, un arbre vide.
    public static func decode(_ data: Data) -> NexusLegacyFileManifest? {
        do {
            let root = try JSONDecoder().decode(Node.self, from: data)
            guard root.children != nil else { return nil }
            var paths: [String] = []
            var stack = [root]
            while let node = stack.popLast() {
                if node.type == "file", let path = node.path {
                    paths.append(path.replacingOccurrences(of: "\\", with: "/"))
                }
                stack.append(contentsOf: node.children ?? [])
            }
            return paths.isEmpty ? nil : NexusLegacyFileManifest(paths: paths.sorted())
        } catch {
            return nil
        }
    }

    /// Les chemins ramenés au dossier du mod installé : parmi les dossiers de
    /// l'archive qui contiennent un `manifest.json`, celui dont les chemins
    /// concordent le mieux avec `installed` — même règle que
    /// `NexusFileManifest.files(matching:)`, sur les chemins seuls.
    ///
    /// `manifest.json` ne compte pas dans la concordance : sans empreinte, il
    /// concorde avec **toute** racine, et l'archive d'un autre composant du
    /// pack passerait pour une version de ce mod.
    ///
    /// `nil` sans racine à `manifest.json` (un optionnel posé par-dessus le
    /// mod n'est pas une version d'auteur), sans concordance, ou à égalité.
    ///
    /// - Parameter installed: clés normalisées (`ModFilePath.key`) du dossier.
    public func paths(matching installed: Set<String>) -> Set<String>? {
        let keys = Set(paths.map(ModFilePath.key))
        var roots: Set<String> = []
        for key in keys {
            if key == "manifest.json" {
                roots.insert("")
            } else if key.hasSuffix("/manifest.json") {
                roots.insert(String(key.dropLast("manifest.json".count)))
            }
        }
        var best: (score: Int, paths: Set<String>)?
        var tie = false
        for root in roots {
            let mapped = Set(keys.filter { $0.hasPrefix(root) }.map { String($0.dropFirst(root.count)) })
            let score = mapped.intersection(installed).subtracting(["manifest.json"]).count
            if score > (best?.score ?? 0) {
                best = (score, mapped)
                tie = false
            } else if score > 0, score == best?.score {
                tie = true
            }
        }
        guard let best, !tie else { return nil }
        return best.paths
    }
}
