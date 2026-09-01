import Foundation

/// Index `UniqueID → nexusID` lu depuis le dump Pathoschild en cache.
///
/// Le dump Pathoschild porte un champ `nexus` sur chaque entrée — c'est
/// l'identifiant Nexus **que Pathoschild tient à jour**, souvent différent
/// de celui que smapi.io connaît ou que le manifest déclare. smapi.io est la
/// source principale, mais elle a deux angles morts sur le parc :
/// 1. elle rend `metadata: nil` pour les mods dont elle n'a pas le statut ;
/// 2. elle omet carrément l'entrée pour les mods dont elle ne sait rien.
///
/// Le cache Pathoschild remplit ces deux angles, **offline** : un mod listé
/// chez Pathoschild voit son `nexusID` attribué sans une seule requête Nexus
/// supplémentaire. Et c'est l'index que `applySmapiResults` consulte pour
/// fabriquer un `Blocked.metadataNexusId` sur les mods sans réponse smapi.io —
/// une fois l'identifiant connu, le recheck Nexus direct (clé API requise)
/// prend le relais.
///
/// Filet, pas substitut : un mod que **ni** smapi.io **ni** Pathoschild ne
/// connaissent (ex. UltraSmooth sur le parc mesuré) reste invisible, et c'est
/// à l'utilisateur de saisir l'identifiant manuellement dans la fiche détail
/// — le champ existe déjà dans l'UI, et son flux est déjà câblé.
///
/// Le cache disque est posé par `PathoschildCompatibilityList.fetch` ; ce type
/// ne fait que **lire** ce cache, sans réseau. Une absence de cache rend un
/// index vide : aucun effet de bord, l'appelant retombe sur smapi.io seul.
public enum PathoschildNexusIndex {

    /// Index `UniqueID → nexusID` filtré aux identifiants positifs.
    /// Les `nexus: null`, `nexus: 0`, `nexus: -1` du dump sont écartés ici.
    public static func loadFromCache(now: Date = Date()) -> [String: Int] {
        guard let data = PathoschildCompatibilityList.loadFreshCache(now: now)
                ?? PathoschildCompatibilityList.cachedAnyAgeNow(),
              let entries = PathoschildCompatibilityList.decode(data) else {
            return [:]
        }
        var out: [String: Int] = [:]
        out.reserveCapacity(entries.count)
        for entry in entries {
            // `id` peut être une liste CSV (`"a.b, a.c"`) pour les renommages ;
            // on indexe chaque identifiant séparément.
            for sub in entry.id.split(separator: ",") {
                let trimmed = sub.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let id = entry.nexusID, id > 0 else { continue }
                out[trimmed] = id
            }
        }
        return out
    }
}

extension PathoschildCompatibilityList {
    /// Cache disque **quel que soit son âge** — exposé pour permettre à
    /// `PathoschildNexusIndex.loadFromCache` de servir un dump potentiellement
    /// périmé, dans le même esprit que `applyPathoschildFallback` qui accepte
    /// déjà un dump d'il y a trois jours quand le réseau est absent.
    /// `nil` quand aucun fichier n'a jamais été posé sur disque.
    static func cachedAnyAgeNow() -> Data? {
        guard let url = cacheURL() else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return data
    }
}