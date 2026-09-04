import Foundation

/// Renommer le dossier d'un mod — et emmener avec lui tout ce qui s'indexe
/// dessus.
///
/// **Pourquoi ça existe.** `ModItem.id` **est** `folderName`, et c'est la clé
/// de tous les magasins persistés. Deux mods peuvent porter le même nom
/// logique — `X` actif et `.X` en pause sont deux dossiers distincts, et sur le
/// parc de référence ce sont deux `[CP] Seaside Sounds` d'auteurs différents.
/// Ils se partagent alors identité, favori, catégorie, identifiant Nexus,
/// horodatage d'activation et configuration de profil ; un `ForEach` n'en rend
/// qu'un ; et un profil qui demande d'échanger leurs états ne peut pas
/// aboutir — les deux déplacements se refusent l'un l'autre.
///
/// Dénouer cet échange par un nom temporaire aurait rendu le profil applicable
/// **sans rien réparer** : les deux mods auraient continué de partager les
/// quatre magasins que la mesure du 2026-09-05 a trouvés sur le parc réel
/// (`installedModRegistry`, sa sauvegarde, `modActivationTimestamps`,
/// `nexusCustomModIds`). Donner un nom distinct à l'un des deux supprime la
/// cause.
///
/// **Ce que ce type porte** : les règles pures — ce qu'un nom vaut, et comment
/// une clé suit son dossier. Le parcours des douze magasins reste au ViewModel,
/// qui seul les connaît ; il est énuméré à un seul endroit, et cette liste doit
/// rester exhaustive.
public enum ModFolderRename {

    /// Pourquoi un nom est refusé. Un cas par raison : l'écran doit pouvoir
    /// dire **laquelle**, une phrase générique n'aide personne à corriger.
    public enum Verdict: Equatable, Sendable {
        case ok
        /// Vide, ou fait de blancs.
        case empty
        /// Un point de tête : c'est la marque de pause, pas une lettre du nom.
        case leadingDot
        /// `/` ou `:` — le premier fabrique un composant de pack, le second est
        /// le séparateur historique du Finder.
        case invalidCharacter
        /// Le nom d'un autre dossier. L'accepter recréerait la collision qu'on
        /// répare.
        case alreadyTaken
        /// Le nom actuel : rien à faire, et surtout pas douze migrations de
        /// magasins pour un renommage qui n'en est pas un.
        case unchanged
    }

    /// Le nom retenu : débarrassé de ses blancs de bord.
    public static func sanitized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ce que vaut `newName` pour le mod dont le nom logique est `current`.
    ///
    /// - Parameter existing: les noms **logiques** de tous les dossiers de
    ///   tête, celui du mod compris.
    public static func validate(_ newName: String,
                                renaming current: String,
                                existing: some Sequence<String>) -> Verdict {
        let name = sanitized(newName)
        guard !name.isEmpty else { return .empty }
        guard !name.hasPrefix(".") else { return .leadingDot }
        guard !name.contains("/"), !name.contains(":") else { return .invalidCharacter }
        // La comparaison ignore la casse : le disque de macOS est insensible à
        // la casse par défaut, donc « seaside » n'ouvre aucune place que
        // « Seaside » n'occupait pas déjà — ni pour le renommage en cours, ni
        // face aux voisins.
        if name.compare(current, options: .caseInsensitive) == .orderedSame {
            return .unchanged
        }
        if existing.contains(where: { $0.compare(name, options: .caseInsensitive) == .orderedSame }) {
            return .alreadyTaken
        }
        return .ok
    }

    /// Le nom **physique** que prend le dossier renommé : l'état de pause est
    /// préservé, et c'est le point de tête qui le porte.
    public static func physicalName(_ logicalName: String, pausedLike currentPhysical: String) -> String {
        (currentPhysical.hasPrefix(".") ? "." : "") + logicalName
    }

    /// Les clés d'un magasin qui suivent un dossier renommé : la sienne, et
    /// celles de ses composants (leur nom logique est le chemin relatif sous
    /// le pack). Un voisin dont le nom *commence* pareil reste — renommer
    /// `Pack` ne touche pas `PackDeLuxe`, la même garde que `ModRemovalPurge`.
    static func movedKeys(in keys: some Sequence<String>, from old: String) -> [String] {
        guard !old.isEmpty else { return [] }
        let componentPrefix = old + "/"
        return keys.filter { $0 == old || $0.hasPrefix(componentPrefix) }
    }

    private static func renamed(_ key: String, from old: String, to new: String) -> String {
        key == old ? new : new + key.dropFirst(old.count)
    }

    /// Ce qu'une clé **partagée** devient quand l'un des deux prétendants se
    /// renomme. Ne s'applique qu'à ce cas : hors collision, une clé suit son
    /// mod, quelle que soit sa nature.
    public enum SharedKeyPolicy: Equatable, Sendable {
        /// Une **préférence** — favori, catégorie, drapeau « sa config suit le
        /// profil », horodatage d'activation. Les deux mods la gardent : la
        /// déplacer ferait perdre au mod resté en place ce qu'elle portait,
        /// pour avoir laissé son voisin se renommer.
        case copy
        /// Une **affirmation sur un mod** — l'identifiant Nexus saisi à la
        /// main, la ligne de registre avec sa date d'installation. Rien ne dit
        /// lequel des deux prétendants elle décrivait. La copier ferait
        /// affirmer au mod renommé quelque chose que personne n'a dit de lui :
        /// il irait chercher ses mises à jour sur la page d'un autre. On la
        /// laisse où elle est — le mod renommé la réapprend de son propre
        /// manifeste au prochain scan.
        case leaveBehind
    }

    /// Fait suivre les clés d'un magasin indexé par nom de dossier.
    ///
    /// - Parameter shared: `true` quand un **autre** mod réclame encore
    ///   l'ancien nom — le cas d'une collision.
    /// - Parameter policy: ce que devient une clé partagée. Ignoré hors
    ///   collision.
    /// - Returns: `true` si quelque chose a bougé. L'appelant ne réécrit le
    ///   disque que dans ce cas.
    @discardableResult
    public static func migrate<Value>(_ store: inout [String: Value],
                                      from old: String, to new: String,
                                      shared: Bool,
                                      policy: SharedKeyPolicy = .copy) -> Bool {
        guard !(shared && policy == .leaveBehind) else { return false }
        let moved = movedKeys(in: store.keys, from: old)
        guard !moved.isEmpty else { return false }
        for key in moved {
            store[renamed(key, from: old, to: new)] = store[key]
            if !shared { store.removeValue(forKey: key) }
        }
        return true
    }

    @discardableResult
    public static func migrate(_ store: inout Set<String>,
                               from old: String, to new: String,
                               shared: Bool,
                               policy: SharedKeyPolicy = .copy) -> Bool {
        guard !(shared && policy == .leaveBehind) else { return false }
        let moved = movedKeys(in: store, from: old)
        guard !moved.isEmpty else { return false }
        for key in moved {
            store.insert(renamed(key, from: old, to: new))
            if !shared { store.remove(key) }
        }
        return true
    }
}
