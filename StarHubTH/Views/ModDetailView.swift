import SwiftUI

/// Rich detail pane for a single mod: header (artwork, name, version/author,
/// Nexus link) plus Description/Changelog segmented tabs rendering
/// `DescriptionBlock`s produced by `StarHubTHViewModel.loadModDetail(for:)`.
/// Lives in the NavigationSplitView detail column (pushed via
/// `vm.viewingModDetail`, wired in `MainView`) — never a sheet/modal, so it
/// behaves like any other master-detail drill-down (back chevron pops it).
///
/// This is a second, temporary entry point into the same rich-content data
/// layer as `ModDetailsPopover` (info button); the popover keeps handling
/// category/Nexus-id editing untouched until the Task 5 migration.
struct ModDetailView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ModItem
    @State private var selectedTab = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Picker("", selection: $selectedTab) {
                    Text(vm.L(L10n.Mods.detailDescription)).tag(0)
                    Text(vm.L(L10n.Mods.detailChangelog)).tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                content
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let extra = vm.modExtra(for: mod), !extra.pictureUrl.isEmpty, let url = URL(string: extra.pictureUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: 200)
                            .clipped()
                    } else if phase.error != nil {
                        EmptyView()               // offline / broken → skip, no placeholder box
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text(mod.name)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)

            HStack(spacing: 6) {
                Text("v\(mod.version)")
                Text("•")
                Text(mod.author)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            let link = vm.nexusLink(for: mod)
            if !link.isEmpty {
                Button {
                    if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text(vm.L(L10n.Mods.nexusOpenPage))
                    }
                    .font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .pointingHandCursor()
            }
        }
    }

    // MARK: Tab content

    @ViewBuilder
    private var content: some View {
        if let state = vm.modDetailState {
            let blocks = selectedTab == 0 ? state.description : state.changelog
            if blocks.isEmpty {
                if state.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ContentUnavailableView(
                        vm.L(L10n.Mods.detailOffline),
                        systemImage: "wifi.slash"
                    )
                    .frame(maxWidth: .infinity, minHeight: 160)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if state.isStale {
                        stalenessHint
                    }
                    DescriptionBlocksView(blocks: blocks, vm: vm)
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 160)
        }
    }

    /// Discreet indicator shown above the content when it was served from
    /// cache/local fallback and a background refresh is in flight (or failed
    /// and was dropped in favor of keeping the last-known-good content).
    private var stalenessHint: some View {
        Label(vm.L(L10n.Mods.detailCached), systemImage: "arrow.triangle.2.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
