import Foundation
import Testing
@testable import StarHubTHCore

/// A1-T11 — le rapport du tri voyage avec le bilan d'un mod, et le résumé
/// chiffré compte les fantômes retirés.
struct InstallReportTriageTests {
    private func report(ghosts: [String] = [], local: [String] = []) -> UpdateTriageReport {
        var report = UpdateTriageReport()
        report.removedGhosts = ghosts
        report.keptLocal = local
        return report
    }

    @Test func aTriageWithSomethingToSayIsNotSilent() {
        let outcome = PreservedDataOutcome(modFolder: "Cropgenics", restored: 0, failed: [],
                                           triage: report(ghosts: ["rift_axe.png"]))
        #expect(!outcome.isSilent)
        let report = InstallReport(installedNames: ["Wildroot"], deltas: [], remainingInQueue: 0,
                                   preserved: [outcome])
        #expect(report.preserved.count == 1)
    }

    /// Des fichiers locaux gardés en silence : le cas ordinaire, rien à dire.
    @Test func onlyLocalFilesKeptStaysSilent() {
        let outcome = PreservedDataOutcome(modFolder: "ItemBags", restored: 0, failed: [],
                                           triage: report(local: ["assets/Modded Bags/bag.json"]))
        #expect(outcome.isSilent)
    }

    @Test func theSummaryCountsRemovedGhosts() {
        let summary = InstallReportSummary.of([], preserved: [
            PreservedDataOutcome(modFolder: "A", restored: 0, failed: [], triage: report(ghosts: ["a", "b"])),
            PreservedDataOutcome(modFolder: "B", restored: 1, failed: []),
        ])
        #expect(summary.ghostsRemoved == 2)
        #expect(summary.dataRestored == 1)
    }
}
