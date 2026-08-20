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

struct TranslationLotBuildTests {

    private func row(_ key: String, english: String, french: String,
                     state: TranslationCoverage.DiffRow.State,
                     component: String? = nil, section: String? = nil) -> TranslationCoverage.DiffRow {
        TranslationCoverage.DiffRow(key: key, english: english, french: french, state: state,
                                    component: component, section: section)
    }

    /// Ce qui a déjà un français ne part pas : le lot ne peut donc pas
    /// l'écraser au retour.
    @Test func onlyRowsWithoutFrenchAreExported() {
        let rows = [row("a", english: "One", french: "", state: .missing),
                    row("b", english: "Two", french: "Deux", state: .translated),
                    row("c", english: "Three", french: "", state: .empty)]
        let lot = TranslationLot.build(mod: "M", language: "fr", rows: rows, glossary: nil)
        #expect(lot.entries.map(\.key) == ["a", "c"])
    }

    /// `TranslationCoverage` stocke le français **brut** : une valeur faite
    /// uniquement d'espaces est classée `.empty` (via `isBlank`) mais n'est
    /// pas la chaîne vide. C'est le cas réel le plus courant — un traducteur
    /// qui laisse un espace plutôt qu'une valeur franchement vide — et il
    /// doit rester exportable, sous peine de clés jamais traduites.
    @Test func rowsWithWhitespaceOnlyFrenchAreStillExported() {
        let rows = [row("c", english: "Three", french: "   ", state: .empty)]
        let lot = TranslationLot.build(mod: "M", language: "fr", rows: rows, glossary: nil)
        #expect(lot.entries.map(\.key) == ["c"])
    }

    /// Une orpheline porte, en pratique, un français **non vide** (la
    /// traduction existante d'une clé disparue de l'anglais) et un anglais
    /// vide : rien à traduire, elle n'a pas de référence.
    @Test func orphanRowsAreNeverExported() {
        let rows = [row("z", english: "", french: "Valeur existante", state: .orphan)]
        #expect(TranslationLot.build(mod: "M", language: "fr", rows: rows,
                                     glossary: nil).entries.isEmpty)
    }

    @Test func everyExportedEntryHasAnEmptyTarget() {
        let rows = [row("a", english: "One", french: "", state: .missing)]
        let lot = TranslationLot.build(mod: "M", language: "fr", rows: rows, glossary: nil)
        #expect(lot.entries.allSatisfy { $0.target.isEmpty })
    }

    /// `component` et `section` doivent atterrir dans le bon champ de
    /// l'entrée — pas l'inverse, ce qu'une simple absence de valeur ne
    /// pourrait pas trahir.
    @Test func componentAndSectionLandInTheRightField() {
        let rows = [row("a", english: "One", french: "", state: .missing,
                        component: "ComponentA", section: "SectionA")]
        let lot = TranslationLot.build(mod: "M", language: "fr", rows: rows, glossary: nil)
        #expect(lot.entries.first?.component == "ComponentA")
        #expect(lot.entries.first?.section == "SectionA")
    }

    /// Les termes imposés voyagent avec l'entrée : le chat n'a pas le
    /// glossaire du jeu, il faut le lui donner.
    @Test func matchedGlossaryTermsTravelWithTheirEntry() {
        let glossary = Glossary(entries: [GlossaryEntry(en: "Iridium Ore",
                                                        fr: "Minerai d'iridium", kind: .item)])
        let rows = [row("a", english: "Give me Iridium Ore", french: "", state: .missing)]
        let lot = TranslationLot.build(mod: "M", language: "fr", rows: rows, glossary: glossary)
        #expect(lot.entries.first?.glossary == ["Iridium Ore": "Minerai d'iridium"])
    }
}
