import Testing
import Foundation
@testable import StarHubTHCore

struct InstallReportTests {

    private func delta(folder: String, configAdded: Int = 0, configRemoved: Int = 0,
                       untranslated: Int = 0, removed: Int = 0) -> ModUpdateKeyDelta {
        let dict = { (n: Int, prefix: String) in
            Dictionary(uniqueKeysWithValues: (0..<n).map { ("\(prefix)\($0)", "v\($0)") })
        }
        return ModUpdateKeyDelta(
            uniqueId: "Mod.\(folder)", folderName: folder, date: Date(),
            config: (configAdded + configRemoved > 0)
                ? KeySetDelta(added: dict(configAdded, "a"),
                              removed: dict(configRemoved, "r"), reconciled: [])
                : nil,
            translation: TranslationKeyDelta(
                addedUntranslated: dict(untranslated, "t"),
                addedAuthorTranslated: [:],
                removedKeys: dict(removed, "x"),
                reconciled: []))
    }

    // MARK: - Résumé

    @Test func emptyDeltasGiveZeroedSummary() {
        #expect(InstallReportSummary.of([]) == InstallReportSummary(
            modsUpdated: 0, translationTodo: 0, configChanges: 0, renamesSuggested: 0))
    }

    @Test func summaryCountsEachModOnce() {
        let s = InstallReportSummary.of([delta(folder: "A", configAdded: 2, untranslated: 5),
                                         delta(folder: "B", configRemoved: 1)])
        #expect(s.modsUpdated == 2)
        #expect(s.configChanges == 3)
        #expect(s.translationTodo == 5)
        #expect(s.renamesSuggested == 0)
    }

    @Test func renamesNetOutOfTranslationTodo() {
        // 4 clés ajoutées dont 2 portent les valeurs des 2 clés disparues :
        // le résumé compte 2 à faire — les lignes de delta, elles,
        // affichent les compteurs bruts (comportement C2-T4 conservé).
        var d = delta(folder: "A", untranslated: 4, removed: 2)
        // Un dictionnaire n'a pas d'ordre : désigner explicitement les deux
        // clés ajoutées qui reprennent les valeurs des clés disparues.
        let addedKeys = d.translation.addedUntranslated.keys.sorted()
        let removedValues = d.translation.removedKeys.values.sorted()
        for (i, key) in addedKeys.prefix(2).enumerated() {
            d.translation.addedUntranslated[key] = removedValues[i]
        }
        let renamed = KeyRenameMatcher.pairsByValue(
            old: d.translation.removedKeys,
            new: d.translation.addedUntranslated)
        #expect(renamed.count == 2)
        d.translation.reconciled = renamed
        let s = InstallReportSummary.of([d])
        #expect(s.renamesSuggested == 2)
        #expect(s.translationTodo == 2)
    }

    // MARK: - File de dépôt

    @Test func queuePushesAdvancesAndEmpties() {
        var q = InstallDropQueue(urls: [])
        #expect(q.isEmpty && q.current == nil)
        let a = URL(fileURLWithPath: "/tmp/a.zip"), b = URL(fileURLWithPath: "/tmp/b.zip")
        q.push([a, b])
        #expect(q.current == a && q.count == 2)
        #expect(q.advance() == a)
        #expect(q.current == b && q.count == 1 && !q.isEmpty)
        #expect(q.advance() == b)
        #expect(q.advance() == nil && q.isEmpty)
    }

    // MARK: - Report

    @Test func reportCarriesFrozenData() {
        let deltas = [delta(folder: "A", untranslated: 1)]
        let report = InstallReport(installedNames: ["Mod A"], deltas: deltas,
                                   remainingInQueue: 2)
        #expect(report.installedNames == ["Mod A"])
        #expect(report.deltas == deltas)
        #expect(report.remainingInQueue == 2)
    }

    // MARK: - A1-T7, les données de mod remises en place

    @Test("Les fichiers remis et les échecs se comptent séparément")
    func aggregatesPreservedData() {
        let s = InstallReportSummary.of([], preserved: [
            PreservedDataOutcome(modFolder: "FarmTypeManager", restored: 3, failed: []),
            PreservedDataOutcome(modFolder: "[FTM] Ridgeside", restored: 2, failed: ["data/a.save"])
        ])
        #expect(s.dataRestored == 5)
        #expect(s.dataFailed == 1)
    }

    @Test("Sans préservation, les deux compteurs restent nuls")
    func noPreservedDataMeansZero() {
        let s = InstallReportSummary.of([])
        #expect(s.dataRestored == 0)
        #expect(s.dataFailed == 0)
    }

    /// Le bilan ne doit pas bavarder : un mod dont rien n'a été préservé ne
    /// prend pas de ligne à l'écran.
    @Test("Un résultat muet n'entre pas dans le rapport")
    func silentOutcomesAreDropped() {
        let r = InstallReport(installedNames: ["X"], deltas: [], remainingInQueue: 0,
                              preserved: [PreservedDataOutcome(modFolder: "X", restored: 0, failed: []),
                                          PreservedDataOutcome(modFolder: "Y", restored: 1, failed: [])])
        #expect(r.preserved.map(\.modFolder) == ["Y"])
    }
}
