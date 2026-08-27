import Foundation

/// Un écart entre le config d'un profil A et celui d'un profil B, au chemin
/// près — le patron de `TranslationKeyDiff` transplanté des fichiers plats
/// aux arbres imbriqués (spec §7).
public struct ConfigKeyDiff: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Seul A (le profil de gauche) porte ce chemin.
        case onlyInA
        /// Les deux le portent, avec des valeurs différentes.
        case valueDiffers
        /// Seul B le porte.
        case onlyInB
    }

    public var id: String { path }
    /// Chemin aplati en pointillé — `Controls.ToggleKey`.
    public let path: String
    /// Valeurs rendues **inline** (`["F1","F2"]`, `"K"`, `1.0`). `nil` du
    /// côté qui ne porte pas le chemin.
    public let valueA: String?
    public let valueB: String?
    public let kind: Kind

    public init(path: String, valueA: String?, valueB: String?, kind: Kind) {
        self.path = path
        self.valueA = valueA
        self.valueB = valueB
        self.kind = kind
    }
}

/// Compare deux configs mémorisés, clé à clé, **dans l'ordre du fichier A**
/// (spec §5.2) — jamais en ordre alphabétique.
public enum ConfigJSONDiff {

    public static func compare(_ a: ConfigJSONTree.Value,
                               _ b: ConfigJSONTree.Value) -> [ConfigKeyDiff] {
        var diffs: [ConfigKeyDiff] = []
        walk(a, b, path: "", into: &diffs)
        return diffs
    }

    private static func walk(_ a: ConfigJSONTree.Value,
                             _ b: ConfigJSONTree.Value,
                             path: String,
                             into diffs: inout [ConfigKeyDiff]) {
        if case .object(let objA) = a {
            if case .object(let objB) = b {
                // Les deux côtés sont des objets : clé à clé, dans l'ordre
                // de A — l'ordre du fichier, jamais alphabétique.
                for key in objA.keys {
                    let childPath = path.isEmpty ? key : "\(path).\(key)"
                    if let valueB = objB.members[key] {
                        walk(objA.members[key] ?? .null, valueB,
                             path: childPath, into: &diffs)
                    } else {
                        markBranch(objA.members[key] ?? .null, path: childPath,
                                   kind: .onlyInA, into: &diffs)
                    }
                }
                for key in objB.keys where objA.members[key] == nil {
                    let childPath = path.isEmpty ? key : "\(path).\(key)"
                    markBranch(objB.members[key] ?? .null, path: childPath,
                               kind: .onlyInB, into: &diffs)
                }
            } else {
                // Objet contre scalaire : la valeur entière diffère.
                appendValueDiff(a, b, path: path, into: &diffs)
            }
            return
        }
        if case .object = b {
            appendValueDiff(a, b, path: path, into: &diffs)
            return
        }
        // Deux feuilles : les littéraux, texte à texte.
        if ConfigJSONTree.inline(a) != ConfigJSONTree.inline(b) {
            appendValueDiff(a, b, path: path, into: &diffs)
        }
    }

    private static func appendValueDiff(_ a: ConfigJSONTree.Value,
                                        _ b: ConfigJSONTree.Value,
                                        path: String,
                                        into diffs: inout [ConfigKeyDiff]) {
        diffs.append(ConfigKeyDiff(path: path,
                                   valueA: ConfigJSONTree.inline(a),
                                   valueB: ConfigJSONTree.inline(b),
                                   kind: .valueDiffers))
    }

    /// Une branche entière manque d'un côté : nommer **chaque feuille** —
    /// c'est la lisibilité, chemin par chemin, que la spec §7 demande. Un
    /// objet vide, lui, est son propre chemin.
    private static func markBranch(_ value: ConfigJSONTree.Value,
                                   path: String,
                                   kind: ConfigKeyDiff.Kind,
                                   into diffs: inout [ConfigKeyDiff]) {
        if case .object(let obj) = value {
            if obj.keys.isEmpty {
                diffs.append(ConfigKeyDiff(path: path,
                                           valueA: kind == .onlyInA ? "{}" : nil,
                                           valueB: kind == .onlyInB ? "{}" : nil,
                                           kind: kind))
                return
            }
            for key in obj.keys {
                let childPath = "\(path).\(key)"
                markBranch(obj.members[key] ?? .null, path: childPath,
                           kind: kind, into: &diffs)
            }
        } else {
            diffs.append(ConfigKeyDiff(path: path,
                                       valueA: kind == .onlyInA ? ConfigJSONTree.inline(value) : nil,
                                       valueB: kind == .onlyInB ? ConfigJSONTree.inline(value) : nil,
                                       kind: kind))
        }
    }
}
