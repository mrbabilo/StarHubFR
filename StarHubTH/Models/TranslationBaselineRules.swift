import Foundation

/// Adopter et détecter : deux fonctions pures, sans disque, sur les rangées du
/// diff et le magasin de références.
///
/// **L'état obsolète est dérivé, jamais stocké.** Le stocker obligerait à
/// l'invalider à chaque changement de fichier ; dérivé, il ne peut pas mentir.
/// C'est le choix de `stardew-i18n-translator` (`resolve_string`), et il est
/// juste.
public enum TranslationBaselineRules {
    /// Les références à poser pour les traductions qu'on voit sans les
    /// connaître.
    ///
    /// Une traduction communautaire déjà sur le disque n'a pas de référence :
    /// sans adoption, elle ne pourra **jamais** être signalée obsolète, faute
    /// de point de comparaison. On l'adopte avec l'anglais *courant*, ce qui
    /// revient à démarrer le compteur aujourd'hui : le passé est perdu, l'avenir
    /// est couvert.
    ///
    /// Idempotent : une clé déjà connue n'est pas réécrite, donc un second
    /// passage rend un dictionnaire vide et l'appelant peut sauter l'écriture.
    public static func adoptions(rows: [TranslationCoverage.DiffRow],
                                 existing: [String: TranslationBaseline.Entry])
        -> [String: TranslationBaseline.Entry] {
        var adopted: [String: TranslationBaseline.Entry] = [:]
        for row in rows {
            // Une rangée sans français n'a rien à dater ; une orpheline n'a pas
            // d'anglais de référence.
            guard row.state != .orphan, !row.french.isEmpty else { continue }
            let key = TranslationBaseline.key(component: row.component, key: row.key)
            guard existing[key] == nil else { continue }
            adopted[key] = TranslationBaseline.Entry(source: row.english, target: row.french)
        }
        return adopted
    }

    /// Les références à réancrer parce que quelqu'un a retraduit.
    ///
    /// Quand le français courant diffère de celui de la référence, la
    /// traduction a été refaite depuis. Sans réancrage, la référence resterait
    /// sur l'ancien couple pour toujours — et comme la détection exige que le
    /// français corresponde à la référence, cette clé ne pourrait plus
    /// **jamais** être signalée obsolète. Une clé retraduite deviendrait un
    /// angle mort permanent.
    ///
    /// Le cas « anglais changé, français figé » est exclu : c'est exactement le
    /// signal qu'on veut garder.
    public static func refreshments(rows: [TranslationCoverage.DiffRow],
                                    existing: [String: TranslationBaseline.Entry])
        -> [String: TranslationBaseline.Entry] {
        var refreshed: [String: TranslationBaseline.Entry] = [:]
        for row in rows {
            guard row.state != .orphan, !row.french.isEmpty else { continue }
            let key = TranslationBaseline.key(component: row.component, key: row.key)
            guard let reference = existing[key], reference.target != row.french else { continue }
            // Le réancrage déplace le couple source/cible, rien d'autre : les
            // drapeaux sont des propriétés de la clé, pas de sa référence.
            // Les reconstruire à `false` effaçait le badge « à relire » d'une
            // valeur écrite par le lot dès la fermeture du dialogue.
            refreshed[key] = TranslationBaseline.Entry(
                source: row.english, target: row.french,
                tokenMismatchAccepted: reference.tokenMismatchAccepted,
                reviewNeeded: reference.reviewNeeded)
        }
        return refreshed
    }

    /// Marque les rangées dont l'anglais a changé depuis leur référence.
    ///
    /// Trois conditions, toutes nécessaires : une référence existe, le français
    /// courant est **identique** à celui de la référence, et l'anglais courant
    /// en diffère. Si le français a changé lui aussi, quelqu'un a retraduit
    /// entre-temps : rien à signaler.
    public static func applying(baseline: [String: TranslationBaseline.Entry],
                                to rows: [TranslationCoverage.DiffRow])
        -> [TranslationCoverage.DiffRow] {
        guard !baseline.isEmpty else { return rows }
        return rows.map { row in
            guard row.state == .translated || row.state == .identicalToSource,
                  let reference = baseline[TranslationBaseline.key(component: row.component,
                                                                    key: row.key)],
                  reference.target == row.french,
                  reference.source != row.english
            else { return row }
            return TranslationCoverage.DiffRow(
                key: row.key, english: row.english, french: row.french, state: .outdated,
                component: row.component, section: row.section, sectionIndex: row.sectionIndex,
                previousEnglish: reference.source)
        }
    }
}
