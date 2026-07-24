import SwiftUI

/// Renders a parsed mod-description/changelog as native SwiftUI, lazily.
struct DescriptionBlocksView: View {
    let blocks: [DescriptionBlock]
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let markdown):
                    Text(.init(markdown))            // Markdown-rendered (bold/italic/links)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .image(let url):
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
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

/// Collapsible spoiler (native disclosure). Content is Markdown.
struct SpoilerView: View {
    let title: String
    let content: String
    @ObservedObject var vm: StarHubTHViewModel
    @State private var isExpanded = false

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
                Text(.init(content))
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
