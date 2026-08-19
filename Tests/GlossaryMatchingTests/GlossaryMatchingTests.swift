import Testing
@testable import StarHubTHCore

/// Tâche 8 du plan P2b — matching whole-word case-sensitive avec réclamation
/// de plage (le terme le plus spécifique gagne ses caractères).
struct GlossaryMatchingTests {

    @Test func iridiumOreBeatsOreOnTheSameSpan() {
        let g = Glossary(entries: [
            .init(en: "Ore", fr: "Minerai", kind: .item),
            .init(en: "Iridium Ore", fr: "Minerai d'iridium", kind: .item),
        ])
        let hits = g.matchEntries(in: "You found Iridium Ore here.")
        #expect(hits.map(\.en) == ["Iridium Ore"])   // « Ore » nu a perdu sa plage
    }

    @Test func caseSensitiveWholeWordOnly() {
        let g = Glossary(entries: [.init(en: "Play", fr: "Jouer", kind: .npc)]) // stoplistée en pratique, le matching ne le sait pas
        #expect(g.matchEntries(in: "Let's play in the rain").isEmpty)  // minuscule : pas un nom propre
        #expect(g.matchEntries(in: "Press Play to begin").map(\.en) == ["Play"])
    }

    @Test func capsAtFifteenTerms() {
        let entries = (0..<20).map { GlossaryEntry(en: "Term\($0)", fr: "Terme\($0)", kind: .item) }
        let source = (0..<20).map { "Term\($0)" }.joined(separator: " ")
        #expect(Glossary(entries: entries).matchEntries(in: source).count == 15)
    }

    @Test func shortTermsIgnored() {
        let g = Glossary(entries: [.init(en: "Qi", fr: "Qi", kind: .npc)])
        #expect(g.matchEntries(in: "Visit Qi today").isEmpty)   // < 3 caractères
    }

    @Test func apostropheAndHyphenLiveInsideTheWord() {
        let g = Glossary(entries: [.init(en: "Iridium", fr: "Iridium FR", kind: .item)])
        #expect(g.matchEntries(in: "l'Iridium brille").isEmpty)   // apostrophe avant : pas une frontière
        #expect(g.matchEntries(in: "Iridium-Ore mix").isEmpty)    // tiret après : pas une frontière
        #expect(g.matchEntries(in: "Un Iridium brille").map(\.en) == ["Iridium"])
    }

    @Test func mrQiMatchesAsIs() {
        let g = Glossary(entries: [.init(en: "Mr. Qi", fr: "M. Qi", kind: .npc)])
        #expect(g.matchEntries(in: "Talk to Mr. Qi tonight.").map(\.en) == ["Mr. Qi"])
    }

    @Test func shorterTermKeepsItsOwnOccurrenceElsewhere() {
        let g = Glossary(entries: [
            .init(en: "Ore", fr: "Minerai", kind: .item),
            .init(en: "Iridium Ore", fr: "Minerai d'iridium", kind: .item),
        ])
        let hits = g.matchEntries(in: "Ore first, then Iridium Ore.")
        #expect(hits.map(\.en) == ["Iridium Ore", "Ore"])   // longueur décroissante ; occurrence libre conservée
    }
}
