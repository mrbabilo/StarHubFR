import Foundation
import Testing
@testable import StarHubTHCore

/// Les cas viennent de descriptions Nexus réelles du cache (2026-10-02), passées
/// dans le vrai `DescriptionBlockParser` puis rendues comme `MarkdownText`.
@Suite struct DescriptionInlineMarkdownTests {
    /// Le texte d'un bloc unique de type texte ou titre.
    private func rendered(_ bbcode: String) throws -> (text: AttributedString, spans: [DescriptionInlineMarkdown.Span]) {
        let blocks = DescriptionBlockParser.parse(bbcode)
        let markdown: String
        switch try #require(blocks.first) {
        case .text(let s), .heading(let s, _): markdown = s
        case .list(let items, _): markdown = try #require(items.first)
        default: Issue.record("bloc inattendu : \(blocks)"); return (AttributedString(), [])
        }
        return DescriptionInlineMarkdown.parse(markdown)
    }

    private func isBold(_ text: AttributedString, _ word: String) -> Bool {
        guard let r = text.range(of: word) else { return false }
        return text[r].runs.allSatisfy { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
    }

    /// Wallet Tools (47136) : le mot coloré coupait le gras du titre en deux.
    @Test func boldAroundAColourSpanRendersAsBold() throws {
        let (text, spans) = try rendered(
            "[size=4]Translations are [color=#ff0000]HIGHLY[/color] encouraged. There is an i18n folder.[/size]")
        let shown = String(text.characters)
        #expect(!shown.contains("*"))
        #expect(shown.contains("Translations are HIGHLY encouraged."))
        #expect(spans.count == 1)
        #expect(spans.first.map { String(text[$0.range].characters) } == "HIGHLY")
        #expect(spans.first?.colorHex?.lowercased() == "#ff0000")
    }

    /// Owl Eggs (43539) : souligné dans le gras (le parseur rogne l'espace final).
    @Test func underlineInsideBoldKeepsBothAndNoDelimiterShows() throws {
        let (text, spans) = try rendered(
            "[list][*][b][u]Barn Owl [/u][/b]- Egg spawns in spring[/*][/list]")
        let shown = String(text.characters)
        #expect(shown == "Barn Owl- Egg spawns in spring")
        #expect(isBold(text, "Barn Owl"))
        #expect(spans.count == 1)
        #expect(spans.first?.underline == true)
        #expect(spans.first.map { String(text[$0.range].characters) } == "Barn Owl")
    }

    /// Fashion Sense-like (27345) : trois balises imbriquées autour d'un titre.
    @Test func nestedItalicUnderlineBoldRendersWithoutDelimiters() throws {
        let (text, _) = try rendered("[list][*][i][u][b]--Conditions--[/b][/u][/i][/*][/list]")
        #expect(String(text.characters) == "--Conditions--")
        #expect(isBold(text, "--Conditions--"))
    }

    /// Plusieurs spans dans un même bloc : chacun garde sa plage exacte.
    @Test func severalSpansKeepTheirOwnRanges() throws {
        let (text, spans) = try rendered(
            "If you [color=#00ff00]like[/color] my [color=#00ffff]mods[/color] please [b]endorse[/b]")
        #expect(String(text.characters) == "If you like my mods please endorse")
        #expect(spans.map { String(text[$0.range].characters) } == ["like", "mods"])
        #expect(isBold(text, "endorse"))
    }

    @Test func plainMarkdownWithoutSpansIsUnchanged() {
        let (text, spans) = DescriptionInlineMarkdown.parse("A **bold** word")
        #expect(String(text.characters) == "A bold word")
        #expect(spans.isEmpty)
    }

    /// Un span mal formé ne laisse jamais de syntaxe interne à l'écran.
    @Test func residualAttributeSyntaxIsScrubbed() {
        let (text, spans) = DescriptionInlineMarkdown.parse("^[orphan text and ^(shcolor: '#ffffff')more")
        let shown = String(text.characters)
        #expect(!shown.contains("shcolor"))
        #expect(!shown.contains("^"))
        #expect(spans.isEmpty)
    }

    /// Aucune sentinelle ne survit, même quand le Markdown consomme le contenu
    /// d'un span (deux astérisques colorés autour d'une phrase).
    @Test func sentinelsNeverReachTheScreen() {
        let (text, _) = DescriptionInlineMarkdown.parse(
            "^[*](shcolor: '#ffff00')If you like my mods consider Endorsing!^[*](shcolor: '#ffff00')")
        let shown = String(text.characters)
        let sentinels = [DescriptionInlineMarkdown.open, DescriptionInlineMarkdown.close,
                         DescriptionInlineMarkdown.openPunct, DescriptionInlineMarkdown.closePunct]
        #expect(!shown.unicodeScalars.contains { sentinels.contains($0) })
        #expect(shown.contains("If you like my mods consider Endorsing!"))
    }

    /// SpaceCore (1348) : `[b][size=5]Compatibility[/size][/b]` — le titre sort
    /// en bloc et laisse un gras qui commence par un saut de ligne, illisible
    /// pour CommonMark. Ses `**` ne doivent pas s'afficher.
    @Test func orphanDoubleAsterisksAreDropped() {
        let (text, _) = DescriptionInlineMarkdown.parse("**\n\nCompatible with 1.6.15+.\n\n**")
        #expect(String(text.characters) == "\n\nCompatible with 1.6.15+.\n\n")
    }

    /// Un `*` seul est un renvoi d'auteur, et le code inline reste intact.
    @Test func singleAsteriskAndInlineCodeAreKept() {
        let (text, _) = DescriptionInlineMarkdown.parse("its own category* here, and `a ** b`")
        #expect(String(text.characters) == "its own category* here, and a ** b")
    }

    /// ArchaeologySkill (22199) via le parseur : `[i]` réduit à de la ponctuation.
    @Test func punctuationOnlyItalicLeavesNoAsterisk() throws {
        let blocks = DescriptionBlockParser.parse("Install required mods[i].\n[/i]Download it.")
        guard case .text(let markdown) = try #require(blocks.first) else {
            Issue.record("bloc inattendu : \(blocks)"); return
        }
        #expect(!String(DescriptionInlineMarkdown.parse(markdown).text.characters).contains("*"))
    }
}
