import Foundation

/// Réécrit UNE alternative clavier d'UN réglage dans le texte d'un
/// `config.json` — la seule écriture du « Plan de raccourcis ».
///
/// Le texte est reparsé puis réécrit par `ConfigJSONTree.write`, comme le fait
/// l'éditeur de configuration : indentation à deux espaces, CRLF perdus. Rien
/// d'autre que la valeur visée ne change.
public enum KeybindPlanWriter {
    public enum Failure: Error, Equatable {
        case unreadable          // fichier illisible ou plus parsable
        case pathMissing         // le keyPath ne retombe plus sur l'arbre
        case alternativeMissing  // l'alternative `from` n'est plus dans la valeur
        case unsupportedValue    // la valeur n'est pas une chaîne (SButton entier…)
    }

    /// Le texte complet réécrit : la seule alternative clavier `from` du
    /// réglage remplacée par `to`, les autres alternatives (manette comprises)
    /// préservées dans leur orthographe d'origine.
    ///
    /// Chaque alternative est reconnue par `KeybindParser`, la grammaire même
    /// qui a détecté le conflit : casse, espaces et jetons entiers se
    /// comportent à l'identique. Les espaces qui entourent l'alternative
    /// remplacée sont conservés.
    public static func rewrittenText(original: String, keyPath: [String],
                                     from: KeybindCombo, to: KeybindCombo) -> Result<String, Failure> {
        guard let tree = ConfigJSONTree.parse(original) else { return .failure(.unreadable) }
        guard let current = value(at: keyPath[...], in: tree) else { return .failure(.pathMissing) }
        guard case .string(let raw) = current else { return .failure(.unsupportedValue) }

        var alternatives = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard let index = alternatives.firstIndex(where: { KeybindParser.parse(.string($0)) == [from] })
        else { return .failure(.alternativeMissing) }

        let old = alternatives[index]
        let lead = old.prefix(while: { $0.isWhitespace })
        let trail = old.reversed().prefix(while: { $0.isWhitespace }).reversed()
        alternatives[index] = String(lead) + to.display + String(trail)

        guard let updated = ConfigEditorModel.apply(.string(alternatives.joined(separator: ",")),
                                                    at: keyPath, to: tree),
              let text = ConfigJSONTree.write(updated)
        else { return .failure(.pathMissing) }
        return .success(text)
    }

    /// Descend l'arbre avec la même syntaxe de segments que
    /// `ConfigEditorModel.apply` (clés d'objet, `[n]` pour les tableaux).
    private static func value(at path: ArraySlice<String>,
                              in tree: ConfigJSONTree.Value) -> ConfigJSONTree.Value? {
        guard let segment = path.first else { return tree }
        switch tree {
        case .object(let object):
            return object.members[segment].flatMap { value(at: path.dropFirst(), in: $0) }
        case .array(let items):
            guard segment.hasPrefix("["), segment.hasSuffix("]"),
                  let i = Int(segment.dropFirst().dropLast()), i >= 0, i < items.count else { return nil }
            return value(at: path.dropFirst(), in: items[i])
        default:
            return nil
        }
    }
}
