import Testing
import Foundation
@testable import StarHubTHCore

struct DescriptionBlockTests {
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
