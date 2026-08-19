import Foundation

/// Tâche 14 du plan P2b — ce que la pré-traduction par lot a le droit de
/// traiter : les clés absentes du `fr.json` (`.missing`) et les clés à
/// valeur vide (`.empty`). Jamais une valeur française existante — une
/// traduction humaine n'est pas écrasée par une machine (spec §8.2).
public enum TranslationBatchPlanner {
    public static func eligibleRows(_ rows: [TranslationCoverage.DiffRow])
        -> [TranslationCoverage.DiffRow] {
        rows.filter { $0.state == .missing || $0.state == .empty }   // l'ordre d'entrée est conservé
    }
}
