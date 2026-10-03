import Testing
import Foundation
@testable import StarHubTHCore

/// E2-T1 — la collecte : des `ModItem` réels (packs dépliés, pauses, anomalies)
/// vers les lignes du rapport. Pur : chaque source de données arrive en
/// paramètre, la lecture disque reste chez l'appelant.
struct ModlistReportCollectorTests {

    private func mod(_ name: String, _ uniqueId: String = "Alpha.Code",
                     folderName: String? = nil,
                     version: String = "1.0.0", enabled: Bool = true,
                     nexusModId: String = "",
                     children: [ModItem]? = nil,
                     isGroup: Bool = false) -> ModItem {
        .init(uniqueId: uniqueId, name: name, folderName: folderName ?? name,
              version: version, author: "a", description: "", nexusUrl: "",
              nexusModId: nexusModId, isEnabled: enabled,
              dependencies: [], children: children, isGroup: isGroup)
    }

    @Test func flattensPacksAndMarksHeader() {
        let pack = mod("Mon Pack", children: [
            mod("Un", "Un.Id", folderName: "Mon Pack/Un"),
            mod("Deux", "Deux.Id", folderName: "Mon Pack/Deux"),
        ], isGroup: true)
        let entries = ModlistReport.collect(mods: [pack])
        #expect(entries.count == 3)
        #expect(entries[0].name == "Mon Pack")
        #expect(entries[0].packComponentCount == 2)
        #expect(entries[1].name == "Un")
        #expect(entries[1].packComponentCount == nil)
        #expect(entries[2].name == "Deux")
    }

    @Test func pausedStateIsPerFolder() {
        let pack = mod("Mon Pack", enabled: false, children: [
            mod("Mon Pack/Un", "Un.Id", enabled: true),
        ], isGroup: true)
        let entries = ModlistReport.collect(mods: [pack])
        #expect(entries[0].isPaused == true)
        #expect(entries[1].isPaused == false)
    }

    @Test func coverageAndNexusSourceMapped() {
        let coverage = ["Solo": TranslationCoverage.Coverage(
            total: 100, translated: 82, missing: [], empty: [],
            orphan: [], identicalToSource: [])]
        let entries = ModlistReport.collect(
            mods: [mod("Solo", nexusModId: "191")],
            coverage: coverage,
            nexusId: { _ in nil })
        #expect(entries[0].frPercent == 82)
        #expect(entries[0].nexusId == "191")
    }

    /// La surcharge manuelle passe avant l'identifiant du manifeste.
    @Test func customNexusIdWins() {
        let entries = ModlistReport.collect(
            mods: [mod("Solo", nexusModId: "191")],
            nexusId: { _ in "8828" })
        #expect(entries[0].nexusId == "8828")
    }

    @Test func missingCoverageAndSource() {
        let entries = ModlistReport.collect(mods: [mod("Nue")], nexusId: { _ in nil })
        #expect(entries[0].frPercent == nil)
        #expect(entries[0].nexusId == nil)
    }

    @Test func anomalyFlowsFromHistory() {
        var history = ModErrorHistory()
        history.mods["Cassé"] = ["1.0.0": .init(
            version: "1.0.0", errorCount: 1, warningCount: 0,
            firstSeen: Date(timeIntervalSince1970: 0),
            lastSeen: Date(timeIntervalSince1970: 0))]
        let entries = ModlistReport.collect(
            mods: [mod("Cassé", version: "1.0.0")],
            history: history)
        #expect(entries[0].anomalyReason != nil)
        #expect(entries[0].anomalyReason?.contains("1 erreur") == true)
        #expect(entries[0].anomalyIsError == true)
    }

    @Test func healthyModHasNoAnomaly() {
        let entries = ModlistReport.collect(mods: [mod("Sain")])
        #expect(entries[0].anomalyReason == nil)
        #expect(entries[0].anomalyIsError == false)
    }
}
