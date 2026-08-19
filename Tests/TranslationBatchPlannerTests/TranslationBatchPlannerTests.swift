import Testing
@testable import StarHubTHCore

/// Tâche 14 du plan P2b — ce que le lot a le droit de traiter : les clés
/// absentes du fr.json et les clés à valeur vide, jamais une valeur
/// française existante (spec §8.2).
struct TranslationBatchPlannerTests {

    private func row(_ key: String, _ state: TranslationCoverage.DiffRow.State)
        -> TranslationCoverage.DiffRow {
        TranslationCoverage.DiffRow(key: key, english: "en\(key)", french: "",
                                    state: state, component: nil)
    }

    @Test func eligibleRowsTakesMissingAndEmptyOnly() {
        let rows = [
            row("gone", .missing), row("blank", .empty), row("done", .translated),
            row("same", .identicalToSource), row("lost", .orphan), row("old", .outdated),
        ]
        let eligible = TranslationBatchPlanner.eligibleRows(rows)
        #expect(eligible.map(\.key) == ["gone", "blank"])   // l'ordre d'entrée est conservé
    }

    @Test func eligibleRowsOnEmptyInputIsEmpty() {
        #expect(TranslationBatchPlanner.eligibleRows([]).isEmpty)
    }
}
