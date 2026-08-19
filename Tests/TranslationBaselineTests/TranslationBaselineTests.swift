import Foundation
import Testing
@testable import StarHubTHCore

/// Tâche 10 du plan P2b — le drapeau « écrit sans être relu » sur les
/// références de traduction. Rétrocompatible : les sidecars posés avant la
/// P2b ne portent pas le champ et décodent à `false` (spec §2.4/§3).
struct TranslationBaselineEntryTests {

    @Test func sidecarBeforeP2bDecodesWithReviewNeededFalse() throws {
        let json = #"{"source":"Hello","target":"Bonjour","tokenMismatchAccepted":false}"#
        let entry = try JSONDecoder().decode(TranslationBaseline.Entry.self,
                                             from: Data(json.utf8))
        #expect(entry.reviewNeeded == false)
    }

    @Test func roundTripKeepsReviewNeeded() throws {
        let entry = TranslationBaseline.Entry(source: "Hello", target: "Bonjour",
                                              reviewNeeded: true)
        let data = try JSONEncoder().encode(entry)
        let back = try JSONDecoder().decode(TranslationBaseline.Entry.self, from: data)
        #expect(back.reviewNeeded == true)
    }

    @Test func reviewNeededDefaultsToFalse() {
        let entry = TranslationBaseline.Entry(source: "a", target: "b")
        #expect(entry.reviewNeeded == false)
    }

    @Test func reviewNeededEncodesAsItsOwnField() throws {
        let data = try JSONEncoder().encode(
            TranslationBaseline.Entry(source: "a", target: "b", reviewNeeded: true))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["reviewNeeded"] as? Bool == true)
    }
}
