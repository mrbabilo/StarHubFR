import Testing
import Foundation
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
}
