import Testing
import Foundation
@testable import StarHubTHCore

struct DescriptionBlockTests {
    // MARK: - Régressions relevées sur une description réelle (SVE, Nexus 3753)

    @Test func nestedSpoilersPairWithTheirOwnClosingTag() {
        // SVE imbrique des spoilers (une galerie repliable par carte). En
        // appariant l'ouvrant au *premier* fermant, le fermant externe restait
        // affiché en clair et le contenu interne échappait au bloc.
        let out = DescriptionBlockParser.parse("[spoiler=Outer]a[spoiler]inner[/spoiler]b[/spoiler]")
        guard case let .spoiler(title, content)? = out.first else {
            Issue.record("attendu un spoiler"); return
        }
        #expect(title == "Outer")
        #expect(content.contains("[spoiler]inner[/spoiler]"))
        #expect(out.count == 1)  // rien après : pas de [/spoiler] orphelin
    }

    @Test func imagesInsideASpoilerStayInsideItsContent() {
        // Conséquence directe du défaut ci-dessus : les images vivant dans un
        // spoiler imbriqué tombaient hors du bloc et s'affichaient en balisage
        // brut. SpoilerView re-parse son contenu, donc il suffit qu'il le reçoive.
        let out = DescriptionBlockParser.parse(
            "[spoiler]before[spoiler][img]https://x/y.png[/img][/spoiler]after[/spoiler]")
        guard case let .spoiler(_, content)? = out.first else {
            Issue.record("attendu un spoiler"); return
        }
        #expect(content.contains("[img]https://x/y.png[/img]"))
        // Le contenu est re-parsé par SpoilerView : le spoiler interne devient
        // un bloc à son tour, et c'est *son* contenu qui porte l'image.
        guard case let .spoiler(_, inner)? = DescriptionBlockParser.parse(content)
            .first(where: { if case .spoiler = $0 { return true } else { return false } })
        else { Issue.record("attendu un spoiler imbriqué"); return }
        #expect(DescriptionBlockParser.parse(inner) == [.image(URL(string: "https://x/y.png")!)])
    }

    @Test func unknownBracketedTextIsNotATagAndSurvives() {
        // « [CP] » n'est pas du BBCode : c'est le nom réel des dossiers de SVE.
        // Le supprimer rendait les instructions d'installation fausses.
        #expect(DescriptionBlockParser.parse("Move the [CP] Stardew Valley Expanded folder")
                == [.text("Move the [CP] Stardew Valley Expanded folder")])
    }

    @Test func bodySizedTextIsNotTurnedIntoBold() {
        // SVE utilise [size=3] 187 fois comme taille de *corps de texte*. En le
        // convertissant en gras sans regarder la valeur, toute la page passait
        // en gras et les vrais titres devenaient indiscernables.
        #expect(DescriptionBlockParser.parse("[size=3]body copy[/size]") == [.text("body copy")])
        #expect(DescriptionBlockParser.parse("[size=4]A heading[/size]") == [.text("**A heading**")])
    }

    @Test func headingAlreadyBoldIsNotDoubleWrapped() {
        // [size=4][b]X[/b][/size] donnait « ****X**** », que la règle « supprimer
        // les emphases vides » réduisait à « X » — perdant le gras du titre.
        #expect(DescriptionBlockParser.parse("[size=4][b]Frontier Farm[/b][/size]")
                == [.text("**Frontier Farm**")])
    }

    @Test func emptyLinkLabelDoesNotLeaveDanglingMarkdown() {
        // [url=X][/url] devenait « [](X) », que le rendu laisse voir sous la
        // forme « ](https://…) ».
        let out = DescriptionBlockParser.parse("[url=https://example.com][/url]")
        if case let .text(t)? = out.first {
            #expect(!t.contains("]("))
        }
    }

    @Test func boldSpanningALinkKeepsItsDelimitersPaired() {
        // Produisait « Follow me on[Twitter**](url) » : le gras fermant
        // atterrissait à l'intérieur du libellé du lien.
        guard case let .text(t)? = DescriptionBlockParser
            .parse("[size=3][b]Follow me on [/b][url=https://x][b]Twitter[/b][/url][/size]").first
        else { Issue.record("attendu du texte"); return }
        // Le libellé du lien peut légitimement être en gras ; ce qui comptait,
        // c'est qu'aucun délimiteur ne reste orphelin et que le lien soit entier.
        #expect(t.contains("[**Twitter**](https://x)"))
        #expect(t.components(separatedBy: "**").count % 2 == 1)  // délimiteurs appariés
        // …et que les deux fragments ne se collent pas (« Follow me onTwitter »).
        #expect(t.contains("on** ["))
    }

    @Test func plainTextIsOneTextBlock() {
        #expect(DescriptionBlockParser.parse("Hello world") == [.text("Hello world")])
    }
    @Test func bbcodeBoldBecomesMarkdown() {
        #expect(DescriptionBlockParser.parse("[b]Hi[/b]") == [.text("**Hi**")])
    }
    @Test func htmlBreaksBecomeNewlines() {
        #expect(DescriptionBlockParser.parse("a<br>b") == [.text("a\nb")])
    }
    @Test func bulletListBecomesDashes() {
        let out = DescriptionBlockParser.parse("[list][*]one[*]two[/list]")
        // .text with "- one" / "- two" lines (exact whitespace tolerant: check content)
        guard case let .text(t)? = out.first else { Issue.record("expected text"); return }
        #expect(t.contains("- one") && t.contains("- two"))
    }
    @Test func imageTagBecomesImageBlock() {
        #expect(DescriptionBlockParser.parse("[img]https://x/y.png[/img]") == [.image(URL(string: "https://x/y.png")!)])
    }
    @Test func spoilerTagBecomesSpoilerBlock() {
        #expect(DescriptionBlockParser.parse("[spoiler=Secret]hidden[/spoiler]") == [.spoiler(title: "Secret", content: "hidden")])
    }
    @Test func mixedTextAndImageSplits() {
        let out = DescriptionBlockParser.parse("before [img]https://x/y.png[/img] after")
        #expect(out == [.text("before"), .image(URL(string: "https://x/y.png")!), .text("after")])
    }
    @Test func malformedInputDoesNotCrashAndReturnsText() {
        // Unbalanced tags must degrade to text, never crash/loop.
        let out = DescriptionBlockParser.parse("[b]oops [img]no-close")
        #expect(!out.isEmpty)
        if case .text = out.first { } else { Issue.record("expected a text block") }
    }
    @Test func emptyInputIsEmpty() {
        #expect(DescriptionBlockParser.parse("") == [])
    }
    @Test func imageTagWithAttributesIsExtracted() {
        // Nexus emits `[img width=550]url[/img]`; the attributes must not
        // prevent tokenization (they used to leave the tag as literal text).
        #expect(DescriptionBlockParser.parse("[img width=550]https://x/y.png[/img]")
            == [.image(URL(string: "https://x/y.png")!)])
    }
    @Test func emphasisWrappingImageDoesNotStrandDelimiters() {
        // `[b][img]…[/img] caption[/b]` must not render a lone `**` around the
        // image; the unbalanced bold is dropped, leaving clean caption text.
        let out = DescriptionBlockParser.parse("[b][img]https://x/y.png[/img] caption[/b]")
        #expect(out == [.image(URL(string: "https://x/y.png")!), .text("caption")])
    }
    @Test func leftoverOrStrayTagsAreStrippedNotShownRaw() {
        // Generic close tags (`[/]`, `[/*]`), unknown tags (`[color=x]`), and a
        // stray unbalanced `[b]` must never reach the screen as literal BBCode.
        #expect(DescriptionBlockParser.parse("a [color=red]b[/color] [b]c[/] d[/*]")
            == [.text("a b c d")])
    }
    @Test func markdownLinkSurvivesTagStripping() {
        // The generic tag strip must not eat a Markdown link `[text](url)`
        // produced by the [url] conversion.
        #expect(DescriptionBlockParser.parse("see [url=https://x/y]here[/url]")
            == [.text("see [here](https://x/y)")])
    }
    @Test func selfClosingImageFormIsExtracted() {
        #expect(DescriptionBlockParser.parse("[img=https://x/y.png] tail")
            == [.image(URL(string: "https://x/y.png")!), .text("tail")])
    }
    @Test func punctuationOnlyEmphasisIsUnwrapped() {
        // `[b]:[/b]` → `**:**` can't render (CommonMark flanking) and would show
        // literal `**`; drop the pointless emphasis, keep the punctuation.
        #expect(DescriptionBlockParser.parse("mods[b]:[/b]") == [.text("mods:")])
        // …but emphasis with real words is preserved.
        #expect(DescriptionBlockParser.parse("[b]Warning:[/b]") == [.text("**Warning:**")])
    }
    @Test func blankLineRunsAreCollapsed() {
        // HTML block tags each became a newline, stacking into large gaps.
        guard case let .text(t)? = DescriptionBlockParser.parse("a\n\n\n\n\nb").first else {
            Issue.record("expected text"); return
        }
        #expect(t == "a\n\nb")
    }
    @Test func horizontalRuleBecomesDivider() {
        #expect(DescriptionBlockParser.parse("one[hr]two")
            == [.text("one"), .divider, .text("two")])
        #expect(DescriptionBlockParser.parse("a[line]b")
            == [.text("a"), .divider, .text("b")])
    }
    @Test func boldWrappedRuleDropsStrayDelimiters() {
        // `[b][hr][/b]` used to render `****` around a literal `---`.
        #expect(DescriptionBlockParser.parse("intro[b][hr][/b]more")
            == [.text("intro"), .divider, .text("more")])
    }
    @Test func emptyEmphasisIsRemoved() {
        #expect(DescriptionBlockParser.parse("x[b][/b]y") == [.text("xy")])
    }
}
