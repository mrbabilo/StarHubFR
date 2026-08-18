import Foundation

/// Le **texte** d'un fichier de traduction : ce qu'il faut écrire, jamais où
/// l'écrire. Pur, donc testable sans toucher au disque.
public enum TranslationDocument {

    public enum DocumentError: Error, Equatable {
        /// Le `default.json` du mod ne se lit pas. Rendre un fichier vide
        /// effacerait la traduction qu'on prétend mettre à jour.
        case sourceUnreadable
        /// Le fichier cible existe mais ne se lit pas. L'écraser jetterait un
        /// travail qu'on n'a pas su lire — pas qu'on a su vide.
        case targetUnreadable
    }

    /// Un fichier cible neuf, dans l'ordre de sa source.
    ///
    /// L'ordre de la source est la seule référence disponible : c'est celui que
    /// l'auteur a choisi, et celui qu'une comparaison ultérieure suivra.
    ///
    /// Une traduction dont la clé n'existe pas dans la source est refusée par
    /// `OrderedJSONWriter` — elle n'aurait pas de rang, et le jeu ne la lirait
    /// jamais.
    public static func create(fromSource sourceText: String,
                              translations: [String: String]) throws -> String {
        do {
            _ = try I18nLenientParser.parse(sourceText)
        } catch {
            throw DocumentError.sourceUnreadable
        }
        return try OrderedJSONWriter.text(
            orderedKeys: deduplicated(I18nOutline.read(sourceText).orderedKeys),
            values: translations)
    }

    /// Applique des modifications à un fichier cible existant.
    ///
    /// L'ordre **du fichier cible** est conservé — c'est celui du traducteur, et
    /// le réordonner sur la source lui réécrirait son travail. Une clé nouvelle
    /// est **ajoutée à la fin**, dans l'ordre où la source la déclare : lui
    /// deviner une place au milieu reviendrait au même.
    ///
    /// Une modification vide **retire** la clé : c'est la forme que prend « je
    /// ne traduis plus celle-ci », et SMAPI retombe alors sur la source.
    public static func apply(edits: [String: String],
                             toTarget targetText: String,
                             sourceText: String) throws -> String {
        let existing: [String: String]
        do {
            existing = try I18nLenientParser.parse(targetText)
        } catch {
            throw DocumentError.targetUnreadable
        }
        do {
            _ = try I18nLenientParser.parse(sourceText)
        } catch {
            throw DocumentError.sourceUnreadable
        }

        var values = existing
        for (key, value) in edits {
            if value.isEmpty { values.removeValue(forKey: key) } else { values[key] = value }
        }

        var order = deduplicated(I18nOutline.read(targetText).orderedKeys)
        let known = Set(order)
        // Les clés nouvelles suivent l'ordre de la source, à la fin : deux
        // ajouts d'une même mise à jour restent ainsi entre eux dans l'ordre que
        // leur auteur leur a donné.
        for key in I18nOutline.read(sourceText).orderedKeys
        where !known.contains(key) && values[key] != nil {
            order.append(key)
        }
        return try OrderedJSONWriter.text(orderedKeys: order, values: values)
    }

    /// L'ordre débarrassé de ses répétitions, **première position gardée**.
    ///
    /// 58 des 2487 fichiers i18n d'un parc réel portent une clé répétée,
    /// `fr.json` compris : refuser de les écrire les rendrait définitivement
    /// inéditables. Le doublon disparaît donc du fichier écrit — une réparation,
    /// dont le `.bak` garde l'original.
    ///
    /// **La règle du jeu, mesurée sur sa `Newtonsoft.Json.dll` le 2026-08-18 :
    /// la position de la première occurrence, la valeur de la dernière.** Cette
    /// fonction tient la première moitié ; `I18nLenientParser` tient la seconde,
    /// en écartant les occurrences non finales. Écrire l'une sans l'autre
    /// changerait en silence un texte affiché en jeu, sur un fichier que le
    /// traducteur n'a pas touché.
    private static func deduplicated(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }
}
