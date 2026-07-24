import SwiftUI

/// Renders a Markdown string as native SwiftUI text, preserving line breaks and
/// inline formatting (bold/italic/links). Built from a precomputed
/// `AttributedString` so the (relatively costly) Markdown parse happens once per
/// value change, never on every layout pass — `Text(.init(String))` would
/// re-parse the `LocalizedStringKey` on each pass, and it also collapses the
/// newlines a mod description relies on.
struct MarkdownText: View {
    private let attributed: AttributedString

    init(_ markdown: String) {
        self.attributed = MarkdownText.render(markdown)
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
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit().frame(maxHeight: 400).clipShape(RoundedRectangle(cornerRadius: 8))
                        } else if phase.error != nil {
                            EmptyView()               // offline / broken → skip
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                        }
                    }
                case .spoiler(let title, let content):
                    SpoilerView(title: title, content: content, vm: vm)
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
