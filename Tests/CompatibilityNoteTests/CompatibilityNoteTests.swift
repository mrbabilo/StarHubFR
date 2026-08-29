import Testing
@testable import StarHubTHCore

/// Les cas viennent de descriptions Nexus réelles, passées dans le vrai
/// `DescriptionBlockParser` le 2026-08-29.
struct CompatibilityNoteTests {

    /// « More Quests » : neuf titres, tous de niveau 3, et la section de
    /// compatibilité est une liste coincée entre deux d'entre eux.
    @Test func aHeadingOpensTheSectionUntilTheNextOfSameLevel() throws {
        let blocks: [DescriptionBlock] = [
            .heading("**Features**", level: 3),
            .list(items: ["a", "b"], ordered: false),
            .heading("**Compatibility**", level: 3),
            .list(items: ["Not compatible with any other Help Wanted mod"], ordered: false),
            .heading("**Translations**", level: 3),
            .text("This mod uses i18n."),
        ]
        let note = CompatibilityNote.find(in: blocks)
        #expect(note?.heading == "Compatibility")
        #expect(note?.blocks == [.list(items: ["Not compatible with any other Help Wanted mod"],
                                       ordered: false)])
    }

    /// **Le corps d'un titre garde son Markdown et parfois du HTML.** Relevé tel
    /// quel : `Who's Compatible?!\n<br />\n<br />`. Sans nettoyage, le titre
    /// affiché serait sale.
    @Test func theHeadingTextIsCleanedOfMarkupResidue() throws {
        let blocks: [DescriptionBlock] = [
            .heading("**Who's Compatible?!**\n<br />\n<br />", level: 2),
            .text("Elle parle de romance entre PNJ — faux positif assumé."),
        ]
        #expect(CompatibilityNote.find(in: blocks)?.heading == "Who's Compatible?!")
    }

    /// Un titre plus petit ne referme pas la section : il en fait partie.
    @Test func aSmallerHeadingStaysInsideTheSection() throws {
        let blocks: [DescriptionBlock] = [
            .heading("Compatibility", level: 2),
            .heading("With SVE", level: 3),
            .text("Not compatible."),
            .heading("Credits", level: 2),
        ]
        let note = CompatibilityNote.find(in: blocks)
        #expect(note?.blocks.count == 2)
    }

    /// Le premier titre gagne : une description qui parlerait deux fois de
    /// compatibilité ne doit pas rendre deux cartes.
    @Test func theFirstMatchingHeadingWins() throws {
        let blocks: [DescriptionBlock] = [
            .heading("Compatibility", level: 3),
            .text("premier"),
            .heading("Compatibilities", level: 3),
            .text("second"),
        ]
        #expect(CompatibilityNote.find(in: blocks)?.blocks == [.text("premier")])
    }

    /// Accents et casse ne doivent pas faire rater un titre français.
    @Test func theMatchIgnoresCaseAndDiacritics() throws {
        let blocks: [DescriptionBlock] = [
            .heading("COMPATIBILITÉ", level: 3), .text("corps"),
        ]
        #expect(CompatibilityNote.find(in: blocks) != nil)
    }

    /// Un titre sans rien dessous ne fait pas une carte vide.
    @Test func aHeadingWithNoBodyYieldsNothing() throws {
        #expect(CompatibilityNote.find(in: [.heading("Compatibility", level: 3)]) == nil)
    }

    /// Aucune des deux formes : on n'invente pas de découpe sur de la prose.
    @Test func proseAloneYieldsNothing() throws {
        let blocks: [DescriptionBlock] = [
            .text("This mod may be incompatible with other mods. Who knows."),
        ]
        #expect(CompatibilityNote.find(in: blocks) == nil)
    }

    // MARK: - Rang 2 : le gras seul sur sa ligne

    /// « Custom Kissing Mod », relevé sur le vrai analyseur : un bloc `.text` de
    /// **neuf lignes** dont `**Compatibility:**`, puis la section continue dans
    /// le bloc `.list` suivant. Un bloc `.text` n'est pas un paragraphe : c'est
    /// tout le texte entre deux éléments structurels, d'où le découpage à la
    /// ligne.
    @Test func aBoldLineAloneOpensTheSection() throws {
        let blocks: [DescriptionBlock] = [
            .text("Adds kissing.\n\n**Compatibility:**\nThis mod may conflict with other mods that change interactions with NPCs."),
            .list(items: ["SMAPI 4.0"], ordered: false),
            .text("**Installation:**\nInstall SMAPI."),
        ]
        let note = CompatibilityNote.find(in: blocks)
        #expect(note?.heading == "Compatibility:")
        #expect(note?.blocks.first == .text("This mod may conflict with other mods that change interactions with NPCs."))
        #expect(note?.blocks[1] == .list(items: ["SMAPI 4.0"], ordered: false))
        #expect(note?.blocks.count == 2)   // le reste du bloc, puis la liste
    }

    /// **Ce que « seul sur sa ligne » retire.** Mesuré : 19 cas sur 22 sont
    /// isolés, 3 sont noyés dans un paragraphe — et ceux-là ouvriraient une
    /// section au milieu d'une phrase.
    @Test func aBoldRunInsideASentenceOpensNothing() throws {
        let blocks: [DescriptionBlock] = [
            .text("This pack **includes compatibility with** the other one, see below."),
        ]
        #expect(CompatibilityNote.find(in: blocks) == nil)
    }

    /// Le titre l'emporte sur le gras : les deux rangs ne se disputent pas.
    @Test func aHeadingWinsOverABoldLine() throws {
        let blocks: [DescriptionBlock] = [
            .text("**Compatibility:**\npar le gras"),
            .heading("Compatibility", level: 3),
            .text("par le titre"),
        ]
        #expect(CompatibilityNote.find(in: blocks)?.blocks == [.text("par le titre")])
    }

    /// Un gras isolé qui ne dit rien de la compatibilité referme la section.
    @Test func theNextBoldLineClosesTheSection() throws {
        let blocks: [DescriptionBlock] = [
            .text("**Compatibility:**\nà lire\n**Credits:**\nà ne pas lire"),
        ]
        #expect(CompatibilityNote.find(in: blocks)?.blocks == [.text("à lire")])
    }

    /// Un bloc `.text` suivant qui contient un gras isolé doit être tronqué à
    /// cette ligne — on garde les lignes d'avant sous forme de `.text`, puis on
    /// s'arrête. La même règle s'applique au bloc ouvreur et aux blocs suivants.
    @Test func aFollowingBlockWithBoldLineInTheMiddleIsTruncated() throws {
        let blocks: [DescriptionBlock] = [
            .text("**Compatibility:**\nfoo"),
            .text("more conflict detail\n**Installation:**\nx"),
        ]
        let note = CompatibilityNote.find(in: blocks)
        #expect(note?.blocks == [.text("foo"), .text("more conflict detail")])
    }
}
