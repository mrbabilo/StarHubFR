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
}
