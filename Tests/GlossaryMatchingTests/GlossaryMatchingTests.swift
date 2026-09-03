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

/// L'index par premier mot — l'accélération de l'appariement, et ce qu'elle
/// n'a pas le droit de changer.
///
/// Un terme ne peut apparaître que si son **premier mot** est présent dans la
/// source comme mot entier : l'appariement exige déjà une frontière de mot de
/// part et d'autre, donc le premier mot du terme y forme forcément un mot
/// entier. Tout le reste du glossaire — 1 126 entrées sur le jeu réel — est
/// écarté sans le chercher.
///
/// Sans cet index, `matchEntries` cherchait les 1 126 termes dans chaque
/// valeur : **9 ms par valeur**, soit 158 s pour préparer le lot de
/// `[CP] Ridgeside Village` (17 519 clés), sur le fil principal.
struct GlossaryMatchingIndexTests {

    @Test func aTermWhoseFirstWordIsAbsentIsNotSearched() {
        let g = Glossary(entries: [.init(en: "Iridium Ore", fr: "Minerai d'iridium", kind: .item)])
        #expect(g.matchEntries(in: "You found some Ore here.").isEmpty)
    }

    @Test func aFirstWordPresentButTruncatedDoesNotMatch() {
        // Le premier mot est là, le terme entier non : l'index le propose,
        // la recherche le refuse. C'est la contre-épreuve de l'index — il
        // filtre, il ne décide pas.
        let g = Glossary(entries: [.init(en: "Iridium Ore", fr: "Minerai d'iridium", kind: .item)])
        #expect(g.matchEntries(in: "Iridium is heavy").isEmpty)
    }

    @Test func theFirstWordIsCutOnTheSameRuleAsTheBoundary() {
        // Le tiret et l'apostrophe vivent **dans** le mot : découper le terme
        // sur l'espace seul rangerait « Bear's Knowledge » sous « Bear »,
        // absent de la source comme mot entier — le terme ne serait plus
        // jamais trouvé.
        let g = Glossary(entries: [
            .init(en: "Bear's Knowledge", fr: "Savoir de l'ours", kind: .item),
            .init(en: "Mr. Qi", fr: "M. Qi", kind: .npc),
        ])
        #expect(g.matchEntries(in: "You got Bear's Knowledge!").map(\.en) == ["Bear's Knowledge"])
        #expect(g.matchEntries(in: "A gift from Mr. Qi").map(\.en) == ["Mr. Qi"])
    }

    @Test func aTermWithoutAnyWordCharacterIsStillSearched() {
        // Rien à indexer : plutôt que de le perdre, il reste cherché
        // systématiquement. Le glossaire du jeu n'en produit aucun — c'est le
        // cas limite d'une entrée importée à la main.
        let g = Glossary(entries: [.init(en: "...", fr: "…", kind: .item)])
        #expect(g.matchEntries(in: "Attends ...").map(\.en) == ["..."])
    }

    @Test func theOrderOfSpecificitySurvivesTheIndex() {
        // Deux termes tirés de deux entrées d'index différentes gardent l'ordre
        // global : le plus long réclame sa plage d'abord.
        let g = Glossary(entries: [
            .init(en: "Ore", fr: "Minerai", kind: .item),
            .init(en: "Iridium Ore", fr: "Minerai d'iridium", kind: .item),
            .init(en: "Bar", fr: "Barre", kind: .item),
        ])
        #expect(g.matchEntries(in: "Iridium Ore into a Bar").map(\.en) == ["Iridium Ore", "Bar"])
    }
}

/// La contre-épreuve que l'index a bel et bien demandée : mesurée sur le parc,
/// pas imaginée. 58 valeurs sur 20 762 rendaient le terme en double avant
/// qu'elle n'existe.
extension GlossaryMatchingIndexTests {

    @Test func aTermIsNotReturnedTwiceWhenItsFirstWordRepeats() {
        // « Bear » deux fois dans la phrase : le terme reste une seule entrée.
        // Sans dédoublonnage des mots, la seconde occurrence réclamait une
        // seconde plage et le terme sortait deux fois — donc deux fois dans le
        // prompt IA et deux chips identiques sous l'éditeur.
        let g = Glossary(entries: [.init(en: "Bear", fr: "Ours", kind: .npc)])
        #expect(g.matchEntries(in: "Small Bear day, everyone wants a Bear.").map(\.en) == ["Bear"])
    }
}
