import Foundation

/// Lecture et écriture des champs du fermier dans un XML de sauvegarde Stardew.
///
/// **Pourquoi un scoping par niveau et pas une simple première occurrence.**
/// Mesuré sur le parc (revue H-T5b, 2026-09-02) : `<gender>` apparaît 41 à 294
/// fois par fichier, et dans `Zofia_443716371` un monstre de `<questLog>` —
/// **imbriqué dans `<player>`** — porte ses propres `<gender>`, `<hair>` et
/// `<maxHealth>` (24) 270 000 caractères avant ceux du fermier. Ni la première
/// occurrence du fichier, ni la première du bloc `<player>`, ne désignent le
/// fermier ; seuls ses **enfants directs** le font. Côté écriture, le défaut
/// était le même et déjà nuisible : éditer une sauvegarde écrivait la santé du
/// fermier dans le monstre et laissait la sienne inchangée.
///
/// Une seule passe produit la table complète : elle remplace la douzaine de
/// balayages regex sur le fichier entier que faisait `parseSaveFile` (36 Mo sur
/// la save principale du parc, à chaque rafraîchissement).
public enum SavePlayerFields {

    /// Valeurs scalaires des balises **enfants directes** de `<player>`.
    ///
    /// Une balise composée (`<hairstyleColor><B>…</B></hairstyleColor>`) est
    /// absente de la table plutôt que présente à vide : l'appelant doit pouvoir
    /// distinguer « pas de valeur » de « valeur vide ». En cas de doublon, la
    /// première valeur gagne — au niveau du fermier, les noms sont uniques.
    public static func directChildren(in xml: String) -> [String: String] {
        var fields: [String: String] = [:]
        forEachDirectChild(in: xml) { name, valueRange in
            if fields[name] == nil {
                fields[name] = XMLEntities.unescape(String(xml[valueRange]))
            }
            return true  // continuer : on veut la table entière
        }
        return fields
    }

    /// Remplace la valeur de l'enfant direct `name` de `<player>`.
    /// - Returns: le XML modifié, ou `nil` si le fermier ne porte pas ce champ —
    ///   l'appelant décide alors s'il retombe sur une écriture non scopée
    ///   (certains champs, comme `goldenWalnuts`, vivent hors de `<player>`).
    public static func replacingDirectChild(
        _ name: String, with value: String, in xml: String
    ) -> String? {
        var found: Range<String.Index>?
        forEachDirectChild(in: xml) { candidate, valueRange in
            guard candidate == name else { return true }
            found = valueRange
            return false  // premier enfant direct portant ce nom : on s'arrête
        }
        guard let range = found else { return nil }
        var modified = xml
        modified.replaceSubrange(range, with: XMLEntities.escape(value))
        return modified
    }

    /// Le bloc `<player>…</player>`, bornes comprises. `nil` si absent.
    public static func playerBlock(in xml: String) -> Substring? {
        guard let start = xml.range(of: "<player>"),
              let end = xml.range(of: "</player>", range: start.upperBound..<xml.endIndex)
        else { return nil }
        return xml[start.lowerBound..<end.upperBound]
    }

    // MARK: - Balayage

    /// Parcourt les enfants directs de `<player>` en une passe, en donnant à
    /// `visit` le nom de la balise et l'intervalle de sa **valeur** (hors
    /// balises). `visit` renvoie `false` pour interrompre le parcours.
    ///
    /// Le parseur est volontairement minimal — pas de `XMLParser` : les saves
    /// du parc font jusqu'à 36 Mo et n'ont besoin que du comptage de niveau.
    /// Il connaît trois formes rencontrées telles quelles dans les fichiers :
    /// l'auto-fermeture (`<basicShipped />`), les attributs
    /// (`<Item xsi:type="Object">`) et les balises composées.
    private static func forEachDirectChild(
        in xml: String,
        _ visit: (String, Range<String.Index>) -> Bool
    ) {
        guard let block = playerBlock(in: xml) else { return }
        var depth = 0
        var pendingName: String?
        var pendingValueStart: String.Index?
        var index = block.startIndex

        while let open = block[index...].firstIndex(of: "<") {
            guard let close = block[open...].firstIndex(of: ">") else { return }
            let tag = block[block.index(after: open)..<close]
            index = block.index(after: close)
            if tag.isEmpty { continue }

            if tag.hasPrefix("/") {
                // Fermeture. Si elle referme l'enfant direct en attente et
                // qu'aucune sous-balise ne s'est ouverte depuis, le texte
                // capturé est bien une valeur scalaire.
                if depth == 2, let name = pendingName, let start = pendingValueStart,
                   tag.dropFirst() == name[...] {
                    if !visit(name, start..<open) { return }
                }
                pendingName = nil
                pendingValueStart = nil
                depth -= 1
                continue
            }
            if tag.hasSuffix("/") {
                // <basicShipped />, <Item xsi:nil="true" />. Une auto-fermée
                // est un enfant, pas une valeur : le parent en cours cesse
                // d'être scalaire. Sans cela, un composé d'auto-fermées
                // seulement — la profondeur n'a pas bougé depuis son ouverture
                // — redevenait éligible à sa fermeture et entrait dans la
                // table avec son markup pour valeur, remplaçable ensuite comme
                // un scalaire.
                pendingName = nil
                pendingValueStart = nil
                continue
            }

            depth += 1
            // Le nom s'arrête au premier espace : `<Item xsi:type="Object">`.
            let name = String(tag.prefix { !$0.isWhitespace })
            if depth == 2 {
                pendingName = name
                pendingValueStart = index
            } else {
                // Une sous-balise s'ouvre : le parent n'a pas de valeur scalaire.
                pendingName = nil
                pendingValueStart = nil
            }
        }
    }
}

/// Type de ferme lu dans `<whichFarm>`.
///
/// Mesuré sur le parc : 3 des 5 fichiers de save portent
/// `<whichFarm>FrontierFarm</whichFarm>` — une **chaîne**, pas un chiffre — et
/// **aucun** ne porte `<whichModFarm>`. L'ancien `Int(...) ?? 0` faisait passer
/// ces fermes pour la ferme standard, vignette et libellé compris.
public enum SaveFarmType {

    /// - Returns: l'index vanilla quand la valeur est un entier ; sinon
    ///   `whichFarm = -1` (la sentinelle « ferme de mod » que
    ///   `SaveFarmNameResolver` traite déjà) et l'identifiant brut, qui est le
    ///   seul nom de la ferme que la sauvegarde porte.
    public static func parse(rawWhichFarm raw: String?) -> (whichFarm: Int, modFarmId: String?) {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return (0, nil)
        }
        if let index = Int(raw) { return (index, nil) }
        return (-1, raw)
    }
}
