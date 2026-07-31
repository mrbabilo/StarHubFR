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
        // [size=3] reste du corps de texte (ni titre, ni gras). [size=4] court est
        // promu en titre de niveau 3 (échelle 4→3, 5→2, 6-7→1) — plus de gras
        // aveugle qui rendait les vrais titres indiscernables du corps.
        #expect(DescriptionBlockParser.parse("[size=3]body copy[/size]") == [.text("body copy")])
        #expect(DescriptionBlockParser.parse("[size=4]A heading[/size]") == [.heading("A heading", level: 3)])
    }

    @Test func headingAlreadyBoldIsNotDoubleWrapped() {
        // [b] dans un [size=4] devient ** avant la promotion en titre ; le gras
        // survit dans le corps du titre (ni double-wrap `****`, ni perte du gras).
        #expect(DescriptionBlockParser.parse("[size=4][b]Frontier Farm[/b][/size]")
                == [.heading("**Frontier Farm**", level: 3)])
    }

    // MARK: - Régressions relevées à l'écran sur le rendu typé

    @Test func sizedRunKeepsTheSpaceThatSeparatesItFromTheTextBefore() {
        // « …directly via » suivi d'un [size=4] séparé par une espace insécable
        // donnait « via**PayPal** » : l'espace consommé collait les deux
        // fragments, et Markdown refuse l'emphase intra-mot — les astérisques
        // s'affichaient donc telles quelles.
        let out = DescriptionBlockParser.parse(
            "[size=3]donating via[/size][size=4]\u{00A0}[b]PayPal[/b][/size]")
        guard case let .text(t)? = out.first else { Issue.record("attendu .text"); return }
        #expect(!t.contains("via**"))
    }

    @Test func sizedLinkLabelStaysInlineAndKeepsItsLink() {
        // Régression apparue avec les titres typés : [url=…][size=4]X[/size][/url]
        // promouvait le libellé en bloc titre, sortant le texte du lien et
        // laissant « ](https://…) » à l'écran.
        let out = DescriptionBlockParser.parse(
            "[url=https://forums.nexusmods.com/user/x][size=4]Poltergeister[/size][/url]")
        guard case let .text(t)? = out.first else { Issue.record("attendu .text"); return }
        #expect(t.contains("Poltergeister"))
        #expect(t.contains("(https://forums.nexusmods.com/user/x)"))
        #expect(!t.hasPrefix("]"))          // pas de crochet fermant orphelin
        #expect(out.count == 1)             // pas de titre extrait en bloc
    }

    @Test func imageTagIsNeverShownAsRawMarkup() {
        // Une [img] doit toujours donner un bloc image, y compris quand elle est
        // enveloppée dans une mise en forme inline.
        let url = URL(string: "https://i.imgur.com/SkgptFd.png")!
        #expect(DescriptionBlockParser.parse("[img]https://i.imgur.com/SkgptFd.png[/img]")
                == [.image(url)])
        #expect(DescriptionBlockParser.parse("[size=4][img]https://i.imgur.com/SkgptFd.png[/img][/size]")
                == [.image(url)])
    }

    @Test func imageInsideAListItemIsHoistedOutAsABlock() {
        // Un item de liste est une chaîne : une [img] qui s'y trouve n'avait
        // nulle part où aller et s'affichait en balisage brut.
        let out = DescriptionBlockParser.parse(
            "[list][*]You're all done[img]https://x/credits.png[/img][/list]")
        #expect(out.contains(.image(URL(string: "https://x/credits.png")!)))
        for case let .list(items, _) in out {
            #expect(items.allSatisfy { !$0.contains("[img") })
        }
    }

    @Test func multilineLinkLabelKeepsItsTextAndDropsTheLink() {
        // Markdown veut un libellé sur une seule ligne. Certains auteurs
        // enveloppent tout un paragraphe dans un [url] : le crochet fermant
        // s'affichait sous la forme « ](https://…) ».
        let out = DescriptionBlockParser.parse(
            "[url=https://github.com/x/y]\n----\nSource code of C# patches[/url]")
        guard case let .text(t)? = out.first else { Issue.record("attendu .text"); return }
        #expect(t.contains("Source code of C# patches"))
        #expect(!t.contains("](https://github.com/x/y)"))
    }

    @Test func colorWrappingACodeBlockDoesNotStrandItsAttribute() {
        // [color=#00FF00][code]…[/code][/color] : le marqueur du bloc code
        // passait pour du texte, la couleur l'enveloppait, puis le tokeniseur
        // extrayait le code en laissant « ](shcolor: '#00FF00') » à l'écran.
        let out = DescriptionBlockParser.parse("[color=#00FF00][code]let x = 1[/code][/color]")
        #expect(out.contains(.code("let x = 1")))
        for case let .text(t) in out { #expect(!t.contains("shcolor")) }
    }

    @Test func nestedColorsResolveInnermostFirst() {
        // Les auteurs imbriquent les couleurs (« tout en blanc, sauf ces mots
        // en vert »). L'appariement non-gourmand tronquait les spans.
        let out = DescriptionBlockParser.parse(
            "[color=#ffffff]If you [color=#00ff00]like[/color] my mods[/color]")
        guard case let .text(t)? = out.first else { Issue.record("attendu .text"); return }
        #expect(t.contains("^[like](shcolor: '#00ff00')"))
        #expect(!t.contains("^(shcolor"))     // pas de span sans libellé
        #expect(t.contains("If you") && t.contains("my mods"))
    }

    @Test func colorOnPunctuationOnlyContentIsDropped() {
        // [color=#ff0]*[/color] produisait le libellé « [*] », que le
        // tokeniseur de listes reprenait comme une puce.
        let out = DescriptionBlockParser.parse("[color=#ffff00]*[/color]Text")
        guard case let .text(t)? = out.first else { Issue.record("attendu .text"); return }
        #expect(!t.contains("shcolor"))
        #expect(t.contains("Text"))
    }

    // MARK: - Nouveaux blocs typés (X2)

    @Test func sizeSixBecomesLevel1Heading() {
        // Échelle 4→3, 5→2, 6-7→1 (1 = le plus grand).
        #expect(DescriptionBlockParser.parse("[size=6]Big Title[/size]")
                == [.heading("Big Title", level: 1)])
    }
    @Test func sizeFiveBecomesLevel2Heading() {
        #expect(DescriptionBlockParser.parse("[size=5]Section[/size]")
                == [.heading("Section", level: 2)])
    }
    @Test func sizeFourParagraphStaysBoldNotHeading() {
        // Garde-fou : un [size=4] sur plus de 80 caractères reste du gras (dans
        // .text), ne devient pas un titre géant.
        let long = String(repeating: "x", count: 90)
        let out = DescriptionBlockParser.parse("[size=4]\(long)[/size]")
        guard case let .text(t)? = out.first else { Issue.record("attendu un .text gras"); return }
        #expect(t.contains("**") && t.contains(long))
    }
    @Test func headingWithoutValueIsLevel2() {
        // [heading] sans valeur → niveau 2 ; [heading=N] suit l'échelle [size].
        #expect(DescriptionBlockParser.parse("[heading]Section[/heading]")
                == [.heading("Section", level: 2)])
    }
    @Test func codeBlockIsVerbatim() {
        // Le contenu de [code] est inviolable : un [b] à l'intérieur ressort
        // littéral, pas converti en **.
        let out = DescriptionBlockParser.parse("[code]config [b]key[/b] = 1[/code]")
        guard case let .code(c)? = out.first else { Issue.record("attendu .code"); return }
        #expect(c == "config [b]key[/b] = 1")
    }
    @Test func quoteBecomesQuoteBlock() {
        #expect(DescriptionBlockParser.parse("[quote]Words of wisdom[/quote]")
                == [.quote("Words of wisdom")])
    }
    @Test func listWithAttributeIsOrdered() {
        // [list=…] avec n'importe quelle valeur → ordonnée, numérotée depuis 1.
        #expect(DescriptionBlockParser.parse("[list=1][*]a[*]b[/list]")
                == [.list(items: ["a", "b"], ordered: true)])
    }
    @Test func centerBecomesCenteredContainer() {
        // [center] enveloppe texte et images : conteneur récursif re-tokenisé.
        let out = DescriptionBlockParser.parse("[center]Hello[/center]")
        guard case let .centered(inner)? = out.first else { Issue.record("attendu .centered"); return }
        #expect(inner == [.text("Hello")])
    }

    // MARK: - Couleur et souligné inline (X2)

    @Test func colorTagBecomesCustomAttribute() {
        // [color=#hex]X[/color] → Markdown à attribut personnalisé shcolor.
        let out = DescriptionBlockParser.parse("[color=#e69138]Warning[/color]")
        guard case let .text(t)? = out.first else { Issue.record("attendu .text"); return }
        #expect(t.contains("shcolor: '#e69138'") && t.contains("Warning"))
        #expect(!t.contains("[color"))   // la balise ne fuit pas
    }
    @Test func colorNameIsResolvedThenCarried() {
        // [color=red] → la table résout « red » en hex ; le shcolor est transporté.
        let out = DescriptionBlockParser.parse("[color=red]Stop[/color]")
        guard case let .text(t)? = out.first else { Issue.record("attendu .text"); return }
        #expect(t.contains("shcolor:"))
        #expect(!t.contains("[color"))
    }
    @Test func unknownColorNameDropsColorKeepsText() {
        // Un nom inconnu est ignoré : le texte reste, sans attribut couleur.
        let out = DescriptionBlockParser.parse("[color=cerulean]Hi[/color]")
        guard case let .text(t)? = out.first else { Issue.record("attendu .text"); return }
        #expect(t.contains("Hi") && !t.contains("shcolor") && !t.contains("[color"))
    }
    @Test func underlineTagBecomesRealUnderline() {
        // [u]X[/u] → attribut shunderline (vrai souligné, plus de l'italique).
        let out = DescriptionBlockParser.parse("[u]underlined[/u]")
        guard case let .text(t)? = out.first else { Issue.record("attendu .text"); return }
        #expect(t.contains("shunderline: 'true'") && t.contains("underlined"))
        #expect(!t.contains("[u]") && !t.contains("[/u]"))   // la balise ne fuit pas
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
    @Test func unorderedListBecomesListBlock() {
        // [list][*]a[*]b[/list] → vrai bloc liste (pas un .text à tirets).
        #expect(DescriptionBlockParser.parse("[list][*]one[*]two[/list]")
                == [.list(items: ["one", "two"], ordered: false)])
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
        // Balises génériques (`[/]`, `[/*]`) et `[b]` dépareillé ne fuitent pas.
        // `[color=red]word[/color]` est converti (porte shcolor), pas supprimé.
        // (Contenu « word » pour éviter qu'il ne commence par la même lettre
        // qu'une balise et fausse la vérification de fuite.)
        let out = DescriptionBlockParser.parse("a [color=red]word[/color] [b]c[/] d[/*]")
        guard case let .text(t)? = out.first else { Issue.record("attendu .text"); return }
        #expect(!t.contains("[color") && !t.contains("[b") && !t.contains("[/"))
        #expect(t.contains("a") && t.contains("word") && t.contains("c") && t.contains("d"))
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
