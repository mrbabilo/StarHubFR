import Foundation
import Testing
@testable import StarHubTHCore

/// P5-10 — le badge compte les mods actifs qui appellent un geste : une mise à
/// jour de la traduction posée, ou une traduction confirmée. Jamais un
/// résultat par le nom.
struct FrenchTranslationBadgeTests {
    private func hit(_ id: Int, _ name: String) -> NexusModSearch.Hit {
        NexusModSearch.Hit(modId: id, name: name, version: "1.0", updatedAt: nil,
                           categoryName: "", uploader: "u", adultContent: false)
    }

    private func candidate(active: Bool = true) -> FrenchTranslationSweep.Candidate {
        .init(folderName: "Tea", name: "Tea", isActive: active, nexusModId: 1)
    }

    @Test func aConfirmedTranslationCountsANameMatchDoesNot() {
        let confirmed = hit(10, "Tea - French")
        let byName = hit(11, "Uncle Iroh Approved Tea")
        let linkedOther = hit(12, "Dateable Robin FR")
        let entry = FrenchTranslationSweep.Entry(hits: [confirmed, byName, linkedOther],
                                                 linkedModIds: [10, 12], searchedAt: .now)
        #expect(FrenchTranslationSweep.callsForAction(.available([confirmed]), candidate: candidate(), entry: entry))
        #expect(!FrenchTranslationSweep.callsForAction(.available([byName, linkedOther]),
                                                       candidate: candidate(), entry: entry))
    }

    @Test func anUpdateOfThePlacedTranslationCounts() {
        #expect(FrenchTranslationSweep.callsForAction(.updateAvailable(hit(10, "Tea FR")),
                                                      candidate: candidate(), entry: nil))
    }

    /// Décision de l'auteur (2026-10-17) : un mod en pause ne compte pas.
    @Test func aPausedModNeverCounts() {
        #expect(!FrenchTranslationSweep.callsForAction(.updateAvailable(hit(10, "Tea FR")),
                                                       candidate: candidate(active: false), entry: nil))
    }

    @Test func settledOrUnknownStatesDoNotCount() {
        for status: FrenchTranslationSweep.Status in [.installed, .installedUnverified, .failed,
                                                      .nothingFound, .notSearched] {
            #expect(!FrenchTranslationSweep.callsForAction(status, candidate: candidate(), entry: nil))
        }
    }
}
