import Testing
@testable import StarHubTHCore

/// Tâche 7 du plan P2b — gate qualité et construction typée.
/// Une règle de gate par test ; la construction vérifie priorité d'assets,
/// règles de clés, appariement et tri déterministe.
struct GlossaryBuilderTests {

    // MARK: - Gate — une règle par test

    @Test func gateAcceptsARealPair() {
        #expect(GlossaryBuilder.passesGate(en: "Iridium Ore", fr: "Minerai d'iridium"))
    }

    @Test func gateRequiresNonEmptySides() {
        #expect(!GlossaryBuilder.passesGate(en: "", fr: "Minerai"))
        #expect(!GlossaryBuilder.passesGate(en: "Iridium", fr: ""))
    }

    @Test func gateRejectsIdenticalENFR() {
        #expect(!GlossaryBuilder.passesGate(en: "Abigail", fr: "Abigail"))
    }

    @Test func gateRequiresTitleCaseEN() {
        #expect(!GlossaryBuilder.passesGate(en: "pip", fr: "Pipou"))
        #expect(GlossaryBuilder.passesGate(en: "Pip", fr: "Pipou"))
    }

    @Test func gateCapsENLengthAt30Characters() {
        // « A » + 29 « a » = 30 caractères pile ; un de plus = rejet.
        let atLimit = "A" + String(repeating: "a", count: 29)
        let overLimit = "A" + String(repeating: "a", count: 30)
        #expect(GlossaryBuilder.passesGate(en: atLimit, fr: "Traduction"))
        #expect(!GlossaryBuilder.passesGate(en: overLimit, fr: "Traduction"))
    }

    @Test func gateCapsENAtFourWords() {
        #expect(GlossaryBuilder.passesGate(en: "One Two Three Four", fr: "Un deux trois quatre"))
        #expect(!GlossaryBuilder.passesGate(en: "One Two Three Four Five", fr: "Un deux trois"))
    }

    @Test func gateRejectsWordCountImbalance() {
        // en : 1 mot ; fr : 3 mots > 1 + 1 → rejet. 2 mots : accepté.
        #expect(!GlossaryBuilder.passesGate(en: "Pumpkin", fr: "Une citrouille jaune"))
        #expect(GlossaryBuilder.passesGate(en: "Pumpkin", fr: "Une citrouille"))
    }

    @Test func gateRejectsStoplistedENCaseInsensitive() {
        #expect(!GlossaryBuilder.passesGate(en: "Play", fr: "Jouer"))
        #expect(!GlossaryBuilder.passesGate(en: "Okay", fr: "D'accord"))
        #expect(!GlossaryBuilder.passesGate(en: "New", fr: "Nouveau"))
        // Hors liste, Majuscule : accepté.
        #expect(GlossaryBuilder.passesGate(en: "Parsnip", fr: "Panais"))
    }

    @Test func gateRejectsSMAPI_TOKENSInEN() {
        #expect(!GlossaryBuilder.passesGate(en: "{{gender}} Hat", fr: "Chapeau"))
    }

    @Test func gateRejectsEndPunctuation() {
        #expect(!GlossaryBuilder.passesGate(en: "Pumpkin.", fr: "Citrouille"))
        #expect(!GlossaryBuilder.passesGate(en: "What?", fr: "Quoi"))
        #expect(GlossaryBuilder.passesGate(en: "Pumpkin Soup", fr: "Soupe de citrouille"))
    }

    @Test func gateRejectsForbiddenCharactersEitherSide() {
        #expect(!GlossaryBuilder.passesGate(en: "Item [rare]", fr: "Objet"))
        #expect(!GlossaryBuilder.passesGate(en: "Objet", fr: "Objet {joli}"))
        #expect(!GlossaryBuilder.passesGate(en: "Two\nLines", fr: "Deux lignes"))
    }

    // MARK: - Construction

    private func build(_ english: [String: [String: String]],
                       _ french: [String: [String: String]]) -> [GlossaryEntry] {
        GlossaryBuilder.build(
            english: { english[$0] },
            french: { french[$0] })
    }

    @Test func itemWinsOverLocationOnSameEN() {
        let entries = build(
            ["Objects": ["70": "Cave", "74": "Iridium Ore"],
             "Locations": ["FarmCave": "Cave"]],
            ["Objects": ["70": "Grotte", "74": "Minerai d'iridium"],
             "Locations": ["FarmCave": "Grotte"]])
        let caves = entries.filter { $0.en == "Cave" }
        #expect(caves.count == 1)
        #expect(caves.first?.kind == .item)
        #expect(caves.first?.fr == "Grotte")
        #expect(entries.contains { $0.en == "Iridium Ore" && $0.fr == "Minerai d'iridium" })
    }

    @Test func weaponsAndToolsKeepOnlyNameKeys() {
        let entries = build(
            ["Weapons": ["Wood_Sword_Name": "Wood Sword",
                         "Wood_Sword_Description": "A basic sword."],
             "Tools": ["Axe_Name": "Axe", "Axe_Description": "Chops wood."]],
            ["Weapons": ["Wood_Sword_Name": "Épée en bois",
                         "Wood_Sword_Description": "Une épée basique."],
             "Tools": ["Axe_Name": "Hache", "Axe_Description": "Coupe du bois."]])
        #expect(entries.map(\.en) == ["Axe", "Wood Sword"])
        #expect(entries.filter { $0.kind == .weapon }.count == 1)
        #expect(entries.filter { $0.kind == .tool }.count == 1)
    }

    /// Les valeurs sont celles du jeu, relevées dans `StringsFromCSFiles` :
    /// les clés `spring`… portent la saison **en minuscules**, les clés
    /// `Utility.cs.5680`… la portent capitalisée. Les deux formes entrent —
    /// le matching est sensible à la casse, `spring` de la prose et
    /// `Spring` d'un titre ont chacun besoin de leur entrée.
    @Test func seasonsOnlyFromStringsFromCSFiles() {
        let entries = build(
            ["StringsFromCSFiles":
                ["spring": "spring", "summer": "summer", "fall": "fall",
                 "winter": "winter", "Utility.cs.5680": "Spring",
                 "Utility.cs.5681": "Summer", "Utility.cs.5682": "Fall",
                 "Utility.cs.5683": "Winter", "Strings.CSFiles.Dog": "Dog"]],
            ["StringsFromCSFiles":
                ["spring": "printemps", "summer": "été", "fall": "automne",
                 "winter": "hiver", "Utility.cs.5680": "Printemps",
                 "Utility.cs.5681": "Été", "Utility.cs.5682": "Automne",
                 "Utility.cs.5683": "Hiver", "Strings.CSFiles.Dog": "Chien"]])
        #expect(entries.count == 8)
        #expect(entries.allSatisfy { $0.kind == .season })
        #expect(entries.contains { $0.en == "spring" && $0.fr == "printemps" })
        #expect(entries.contains { $0.en == "Spring" && $0.fr == "Printemps" })
        // « Dog » est une clé non-saison : ignorée même si appariée.
        #expect(!entries.contains { $0.en == "Dog" })
    }

    /// La minuscule initiale ne disqualifie **que** hors table de saisons :
    /// la gate reste stricte partout ailleurs (un fragment d'UI en
    /// minuscules n'est pas un terme).
    @Test func lowercaseStaysRejectedOutsideTheSeasonTable() {
        let entries = build(
            ["Objects": ["74": "iridium ore"]],
            ["Objects": ["74": "minerai d'iridium"]])
        #expect(entries.isEmpty)
    }

    @Test func keyWithoutFrenchCounterpartProducesNothing() {
        let entries = build(
            ["Objects": ["74": "Iridium Ore", "128": "Parsnip"]],
            ["Objects": ["74": "Minerai d'iridium"]])
        #expect(entries.map(\.en) == ["Iridium Ore"])
    }

    @Test func missingAssetsAreIgnoredWithoutError() {
        #expect(build([:], [:]).isEmpty)
        #expect(build(["Objects": ["74": "Iridium Ore"]], [:]).isEmpty)
    }

    @Test func gateAppliesToConstruction() {
        let entries = build(
            ["Objects": ["1": "Abigail", "2": "Parsnip", "3": "play"]],
            ["Objects": ["1": "Abigail", "2": "Panais", "3": "jouer"]])
        // « Abigail » : en == fr → rejet ; « play » : minuscule + stoplist → rejet.
        #expect(entries.map(\.en) == ["Parsnip"])
    }

    @Test func deterministicSortByENAscending() {
        let entries = build(
            ["Objects": ["a": "Zucchini", "b": "Ancient Fruit", "c": "Apple"]],
            ["Objects": ["a": "Courgette", "b": "Fruit ancien", "c": "Pomme"]])
        #expect(entries.map(\.en) == ["Ancient Fruit", "Apple", "Zucchini"])
    }

    /// Sept valeurs du jeu traînent une espace (`Tesson prismatique `,
    /// `Coffre Junimo `…). Un terme imposé au modèle ne doit pas la porter.
    @Test func surroundingWhitespaceIsTrimmedFromBothSides() {
        let entries = build(
            ["Objects": ["74": " Prismatic Shard "]],
            ["Objects": ["74": "Tesson prismatique  "]])
        #expect(entries == [GlossaryEntry(en: "Prismatic Shard",
                                          fr: "Tesson prismatique", kind: .item)])
    }
}
