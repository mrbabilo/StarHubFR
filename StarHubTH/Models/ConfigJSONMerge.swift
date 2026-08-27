import Foundation

/// Le merge d'une restauration : le disque a grandi depuis la mémorisation,
/// l'utilisateur veut ses réglages. Le verbatim rendait l'un au prix de
/// l'autre ; le merge rend les deux (spec §5.3).
///
/// Le cas réellement couvert est étroit : **le mod a été mis à jour depuis la
/// mémorisation et a gagné des clés.** Rien d'autre n'est promis, et tout
/// ce qui ne se parse pas retombe sur le verbatim de l'étape 2.
public enum ConfigJSONMerge {

    public struct Result: Equatable {
        /// Le texte fusionné, au format SMAPI — déjà passé par la garde de
        /// relecture de `write`.
        public let text: String
        /// Combien de chemins de clés viennent du mémorisé et manquaient au
        /// disque. Le compte que le journal annonce — et rien d'autre.
        public let addedKeyPaths: Int

        public init(text: String, addedKeyPaths: Int) {
            self.text = text
            self.addedKeyPaths = addedKeyPaths
        }
    }

    /// `nil` = pas de merge possible (un texte illisible, ou une relecture
    /// qui échoue). **Le caller doit alors écrire le mémorisé verbatim** —
    /// c'est le comportement de l'étape 2, et il reste le repli.
    public static func mergedText(disk: String, memorized: String) -> Result? {
        guard case .object(let base)? = ConfigJSONTree.parse(disk),
              case .object(let overlay)? = ConfigJSONTree.parse(memorized) else { return nil }
        var added = 0
        let merged = merge(base: base, overlay: overlay, added: &added)
        guard let text = ConfigJSONTree.write(.object(merged)) else { return nil }
        return Result(text: text, addedKeyPaths: added)
    }

    /// Objets : récursion. Toute autre valeur de l'overlay : remplacement
    /// en entier. Clé absente de la base : ajoutée en queue, comptée.
    private static func merge(base: ConfigJSONTree.Object,
                              overlay: ConfigJSONTree.Object,
                              added: inout Int) -> ConfigJSONTree.Object {
        var keys = base.keys
        var members = base.members
        for key in overlay.keys {
            guard let overlayValue = overlay.members[key] else { continue }
            if let baseValue = members[key] {
                if case .object(let baseObject) = baseValue,
                   case .object(let overlayObject) = overlayValue {
                    members[key] = .object(merge(base: baseObject,
                                                 overlay: overlayObject,
                                                 added: &added))
                } else {
                    members[key] = overlayValue
                }
            } else {
                keys.append(key)
                members[key] = overlayValue
                // La clé apportée elle-même, plus ses descendants : une
                // feuille compte 1, un objet compte 1 par chemin interne.
                added += 1 + countKeyPaths(of: overlayValue)
            }
        }
        return ConfigJSONTree.Object(keys: keys, members: members)
    }

    /// Combien de chemins un sous-arbre apporte — le compte annoncé au
    /// journal doit être celui des **clés** ajoutées, feuilles comprises.
    private static func countKeyPaths(of value: ConfigJSONTree.Value) -> Int {
        switch value {
        case .object(let obj):
            return obj.keys.reduce(0) { sum, key in
                sum + 1 + countKeyPaths(of: obj.members[key] ?? .null)
            }
        default:
            return 0
        }
    }
}
