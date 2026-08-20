import Foundation
import Testing
@testable import StarHubTHCore

struct TranslationLotTests {

    private func entry(_ key: String, _ source: String,
                       component: String? = nil) -> TranslationLot.Entry {
        TranslationLot.Entry(component: component, key: key, source: source,
                             section: nil, glossary: [:], target: "")
    }

    /// L'empreinte lie le lot à **un** mod, **une** langue et **un** jeu de
    /// sources anglaises. Elle est ce qui permet de refuser un fichier revenu
    /// après une mise à jour du mod.
    @Test func theDigestIsStableForTheSameContent() {
        let a = TranslationLot.digest(mod: "SVE", language: "fr",
                                      entries: [entry("a", "One"), entry("b", "Two")])
        let b = TranslationLot.digest(mod: "SVE", language: "fr",
                                      entries: [entry("a", "One"), entry("b", "Two")])
        #expect(a == b)
        #expect(!a.isEmpty)
    }

    /// L'ordre des entrées ne doit pas changer l'empreinte : c'est un jeu de
    /// clés, pas une séquence.
    @Test func theDigestIgnoresTheOrderOfEntries() {
        #expect(TranslationLot.digest(mod: "SVE", language: "fr",
                                      entries: [entry("a", "One"), entry("b", "Two")])
                == TranslationLot.digest(mod: "SVE", language: "fr",
                                         entries: [entry("b", "Two"), entry("a", "One")]))
    }

    @Test func changingTheEnglishChangesTheDigest() {
        #expect(TranslationLot.digest(mod: "SVE", language: "fr", entries: [entry("a", "One")])
                != TranslationLot.digest(mod: "SVE", language: "fr", entries: [entry("a", "Un")]))
    }

    @Test func theModAndTheLanguageAreBoundIn() {
        let base = TranslationLot.digest(mod: "SVE", language: "fr", entries: [entry("a", "One")])
        #expect(base != TranslationLot.digest(mod: "RSV", language: "fr",
                                              entries: [entry("a", "One")]))
        #expect(base != TranslationLot.digest(mod: "SVE", language: "de",
                                              entries: [entry("a", "One")]))
    }

    /// Deux composants peuvent définir la même clé : ce sont deux entrées,
    /// et l'empreinte doit les distinguer.
    @Test func twoComponentsWithTheSameKeyAreTwoEntries() {
        #expect(TranslationLot.digest(mod: "M", language: "fr",
                                      entries: [entry("a", "One", component: "A")])
                != TranslationLot.digest(mod: "M", language: "fr",
                                         entries: [entry("a", "One", component: "B")]))
    }

    /// Le fichier se relit lui-même : ce qu'on écrit, on sait le rouvrir.
    @Test func theDocumentSurvivesAJsonRoundTrip() throws {
        let lot = TranslationLot(mod: "SVE", language: "fr",
                                 entries: [entry("a", "One")])
        let data = try JSONEncoder().encode(lot)
        let back = try JSONDecoder().decode(TranslationLot.self, from: data)
        #expect(back.mod == "SVE")
        #expect(back.entries.count == 1)
        #expect(back.digest == lot.digest)
    }

    /// Les consignes voyagent dans le fichier : c'est ce qui permet de le
    /// déposer tel quel dans un chat, sans rien rédiger.
    @Test func theDocumentCarriesItsOwnInstructions() {
        let lot = TranslationLot(mod: "SVE", language: "fr", entries: [entry("a", "One")])
        let text = lot.instructions.joined(separator: " ")
        #expect(text.contains("target"))       // où écrire la traduction
        #expect(text.contains("source"))       // ce qu'il ne faut pas modifier
        #expect(lot.instructions.count >= 4)
    }
}
