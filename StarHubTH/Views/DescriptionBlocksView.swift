import SwiftUI

/// A description image rendered at (up to) its **native** size: it downscales
/// to fit the pane when wider, but is never upscaled — the previous
/// `resizable().scaledToFit()` blew small inline icons up to the full pane
/// width, making them huge and blurry. Loads via a shared in-memory cache so
/// re-renders (tab switches, scrolling) don't refetch.
struct DescriptionImage: View {
    let url: URL
    @State private var image: NSImage?
    @State private var failed = false

    private static let cache = NSCache<NSURL, NSImage>()

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    // Cap at the native width so it never upscales; scaledToFit
                    // still shrinks it to the pane when the pane is narrower.
                    .frame(maxWidth: image.size.width, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if failed {
                EmptyView()                       // offline / broken → skip
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        if let cached = Self.cache.object(forKey: url as NSURL) {
            image = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = NSImage(data: data) {
                Self.cache.setObject(img, forKey: url as NSURL)
                image = img
            } else {
                failed = true
            }
        } catch {
            failed = true
        }
    }
}

/// Renders a Markdown string as native SwiftUI text, preserving line breaks and
/// inline formatting (bold/italic/links). Built from a precomputed
/// `AttributedString` so the (relatively costly) Markdown parse happens once per
/// value change, never on every layout pass — `Text(.init(String))` would
/// re-parse the `LocalizedStringKey` on each pass, and it also collapses the
/// newlines a mod description relies on.
struct MarkdownText: View {
    private let attributed: AttributedString
    /// Whether any run carries a link, so we can show the pointing-hand cursor
    /// over this block (SwiftUI `Text` can't scope a cursor to just the link
    /// sub-range without an AppKit text view, so the hint covers the block).
    private let hasLink: Bool

    init(_ markdown: String) {
        let a = MarkdownText.render(markdown)
        self.attributed = a
        self.hasLink = a.runs.contains { $0.link != nil }
    }

    /// Inline-only parse that *preserves* whitespace/newlines (so multi-line
    /// descriptions and list lines stay on their own line) and degrades to the
    /// raw string rather than throwing on malformed Markdown or stray `%`.
    static func render(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(s)
    }

    var body: some View {
        Text(attributed)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(LinkHandCursor(active: hasLink))
    }
}

/// Applies the pointing-hand cursor only when the text actually contains a link.
private struct LinkHandCursor: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.pointingHandCursor() } else { content }
    }
}

/// Renders a parsed mod-description/changelog as native SwiftUI.
///
/// Uses a plain (eager) `VStack`, matching upstream: a `LazyVStack` here is
/// counter-productive because a description tokenizes into only a handful of
/// blocks — often a single very tall `.text` — and lazily measuring a few huge
/// items inside a `ScrollView` thrashes layout instead of helping.
struct DescriptionBlocksView: View {
    let blocks: [DescriptionBlock]
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let markdown):
                    MarkdownText(markdown)
                case .image(let url):
                    DescriptionImage(url: url)
                case .spoiler(let title, let content):
                    SpoilerView(title: title, content: content, vm: vm)
                case .divider:
                    Divider().padding(.vertical, 4)
                }
            }
        }
    }
}

/// Collapsible spoiler (native disclosure). The content is re-parsed into
/// blocks so it renders images and nested formatting just like the top-level
/// description — upstream rendered spoiler content as a single Markdown string,
/// leaving any `[img]` inside shown as raw BBCode.
struct SpoilerView: View {
    let title: String
    private let blocks: [DescriptionBlock]
    @ObservedObject var vm: StarHubTHViewModel
    @State private var isExpanded = false

    init(title: String, content: String, vm: StarHubTHViewModel) {
        self.title = title
        self.blocks = DescriptionBlockParser.parse(content)
        self.vm = vm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                    Text((title.isEmpty || title == "Spoiler") ? vm.L(L10n.Mods.spoiler) : title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(isExpanded ? vm.L(L10n.Mods.spoilerHide) : vm.L(L10n.Mods.spoilerShow))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            if isExpanded {
                DescriptionBlocksView(blocks: blocks, vm: vm)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
