import Testing
import Foundation
@testable import StarHubTHCore

/// Un accord qui survivrait à une modification serait pire que pas d'accord :
/// il laisserait passer une vraie erreur au nom d'une décision prise pour une
/// autre phrase.
struct TranslationWaiverTests {

    @Test func anAcceptedEntryStopsBlockingThatExactPair() {
        let entry = TranslationWaiver.accepting(source: "Hi ${him^her}$", target: "Salut")
        #expect(TranslationWaiver.isAccepted(entry, source: "Hi ${him^her}$", target: "Salut"))
    }

    @Test func aChangedEnglishSourceVoidsTheAgreement() {
        let entry = TranslationWaiver.accepting(source: "Hi ${him^her}$", target: "Salut")
        #expect(TranslationWaiver.isAccepted(entry, source: "Hello ${him^her}$",
                                             target: "Salut") == false)
    }

    @Test func anEditedTranslationVoidsTheAgreement() {
        let entry = TranslationWaiver.accepting(source: "Hi ${him^her}$", target: "Salut")
        #expect(TranslationWaiver.isAccepted(entry, source: "Hi ${him^her}$",
                                             target: "Salut à toi") == false)
    }

    @Test func anOrdinaryEntryNeverCountsAsAccepted() {
        // Une entrée posée par l'adoption normale du baseline n'est pas un
        // accord : sans quoi toute clé déjà traduite vaudrait blanc-seing.
        let ordinary = TranslationBaseline.Entry(source: "Hi", target: "Salut")
        #expect(TranslationWaiver.isAccepted(ordinary, source: "Hi", target: "Salut") == false)
        #expect(TranslationWaiver.isAccepted(nil, source: "Hi", target: "Salut") == false)
    }

    @Test func anEntryWrittenBeforeThisFeatureStillDecodes() throws {
        // Rétrocompatibilité : les baselines déjà sur le disque n'ont pas le
        // champ. Les refuser effacerait des références réelles, et avec elles
        // la seule preuve qu'une traduction a été faite sur un anglais donné.
        let old = Data(#"{"source":"Hi","target":"Salut"}"#.utf8)
        let entry = try JSONDecoder().decode(TranslationBaseline.Entry.self, from: old)
        #expect(entry.source == "Hi")
        #expect(entry.target == "Salut")
        #expect(entry.tokenMismatchAccepted == false)
    }

    @Test func anAgreementSurvivesAnEncodeDecodeRoundTrip() throws {
        let entry = TranslationWaiver.accepting(source: "Hi ${him^her}$", target: "Salut")
        let data = try JSONEncoder().encode(entry)
        let back = try JSONDecoder().decode(TranslationBaseline.Entry.self, from: data)
        #expect(back == entry)
        #expect(back.tokenMismatchAccepted)
    }
}
