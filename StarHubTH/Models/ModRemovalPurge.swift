import Foundation

/// Ce qu'il faut oublier d'un mod quand on le supprime.
///
/// **Le problème.** `deleteMod` purgeait les favoris, l'historique d'erreurs, la
/// référence de traduction et la couverture FR — mais laissait quatre magasins
/// indexés sur le même nom de dossier logique : le drapeau « sa config suit le
/// profil », l'horodatage d'activation, l'identifiant Nexus saisi à la main et
/// la catégorie choisie. Deux conséquences, l'une visible et l'autre rare mais
/// coûteuse : la vitrine Découverte continue d'afficher « Je l'ai » pour un mod
/// supprimé dans la même session, et un dossier **réutilisé par un autre mod**
/// hérite du drapeau « sa config suit le profil » — au prochain changement de
/// profil, on lui restaure la configuration du disparu.
///
/// **La règle, tranchée le 2026-09-04 : on efface tout.** Ce qu'on supprime
/// disparaît, et une réinstallation repart d'une page blanche. L'alternative —
/// garder ce qui décrit le mod (identifiant Nexus, catégorie) et n'effacer que
/// ce qui suit le dossier — a été écartée : elle laisse deux traces invisibles
/// que rien ne vient jamais nettoyer, pour épargner une ressaisie rare.
///
/// **Pourquoi un type à part.** Le filtrage est pur, et il porte une garde qui
/// mérite d'être éprouvée : un pack supprimé emporte ses composants (leur
/// `folderName` est le chemin relatif sous le pack), mais un voisin dont le nom
/// *commence* pareil doit rester — supprimer `Pack` ne touche pas `PackDeLuxe`.
public enum ModRemovalPurge {

    /// Les clés d'un magasin qu'il faut retirer quand `folderName` disparaît :
    /// la sienne, et celles de ses composants.
    ///
    /// La comparaison porte sur le nom **logique**. Le point de tête d'un mod
    /// en pause vit sur `physicalFolderName` et aucun magasin n'est indexé
    /// dessus : `.Pack` n'est donc pas ramassé au passage — ce serait l'entrée
    /// d'un autre mod, `X` actif et `.X` en pause pouvant être deux mods
    /// distincts (cas réel du parc).
    public static func keysToRemove(from keys: some Sequence<String>,
                                    removing folderName: String) -> Set<String> {
        guard !folderName.isEmpty else { return [] }
        let componentPrefix = folderName + "/"
        return Set(keys.filter { $0 == folderName || $0.hasPrefix(componentPrefix) })
    }

    /// Purge un magasin indexé par nom de dossier. Rend `true` quand quelque
    /// chose a été retiré — l'appelant ne réécrit le disque que dans ce cas.
    @discardableResult
    public static func purge<Value>(_ store: inout [String: Value],
                                    removing folderName: String) -> Bool {
        let doomed = keysToRemove(from: store.keys, removing: folderName)
        guard !doomed.isEmpty else { return false }
        for key in doomed { store.removeValue(forKey: key) }
        return true
    }

    @discardableResult
    public static func purge(_ store: inout Set<String>,
                             removing folderName: String) -> Bool {
        let doomed = keysToRemove(from: store, removing: folderName)
        guard !doomed.isEmpty else { return false }
        store.subtract(doomed)
        return true
    }
}
