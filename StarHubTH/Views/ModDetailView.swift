import SwiftUI

/// Rich detail pane for a single mod: header (artwork, name, version/author,
/// Nexus link), a settings section (category override + Nexus-id editor), and
/// Description/Changelog/Dependencies segmented tabs — the last rendering
/// `DescriptionBlock`s produced by `StarHubTHViewModel.loadModDetail(for:)`.
/// Lives in the NavigationSplitView detail column (pushed via
/// `vm.viewingModDetail`, wired in `MainView`) — never a sheet/modal, so it
/// behaves like any other master-detail drill-down (back chevron pops it).
///
/// The caller (`MainView`) applies `.id(mod.folderName)` to this view so a
/// fresh instance is created whenever the user switches to a different mod:
/// that resets `selectedTab` and, more importantly, the Nexus-id draft below
/// so an in-progress edit can never leak onto the wrong mod's folder.
struct ModDetailView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ModItem
    @State private var selectedTab = 0

    /// Draft text for the Nexus mod id field. Seeded once in `.onAppear` from
    /// the mod's effective id; safe to seed unconditionally (no "already
    /// seeded" guard needed) because the `.id(mod.folderName)` at the call
    /// site gives this view a fresh instance — and therefore a fresh
    /// `@State` — per mod.
    @State private var nexusIdDraft: String = ""

    /// On-demand metadata fetch status (triggered after the user saves a new
    /// Nexus mod id). `.idle` hides the status row; `.loading` shows a spinner.
    @State private var fetchStatus: FetchStatus = .idle

    enum FetchStatus: Equatable {
        case idle
        case loading
        case success(categoryName: String?, latestVersion: String?)
        case noApiKey
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed hero + tab bar — both stay pinned while the tab content
            // below scrolls.
            heroBanner
            tabBar
            ScrollView {
                content
                    .frame(maxWidth: 700, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear { seedDraft() }
    }

    /// The Description / Changelog / Dependencies switcher, pinned under the
    /// hero (outside the ScrollView) so it stays visible while scrolling.
    private var tabBar: some View {
        Picker("", selection: $selectedTab) {
            Text(vm.L(L10n.Mods.detailDescription)).tag(0)
            Text(vm.L(L10n.Mods.detailChangelog)).tag(1)
            Text(vm.L(L10n.Profiles.dependencies)).tag(2)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 700)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: Hero banner (full-width illustration + full-width metadata band)

    private var heroBanner: some View {
        VStack(spacing: 0) {
            bannerImage
            headerBand
        }
    }

    /// Compact edge-to-edge illustration (shorter than a full hero image) so the
    /// pinned banner doesn't eat the pane. Omitted when there's no picture.
    @ViewBuilder
    private var bannerImage: some View {
        if let extra = vm.modExtra(for: mod), !extra.pictureUrl.isEmpty, let url = URL(string: extra.pictureUrl) {
            CachedAsyncImage(url: url)
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .clipped()
        }
    }

    /// Compact metadata band under the image: name + category + links on the
    /// left, the metadata (updated / installed / languages) stacked on the
    /// right. The name sits on a solid tinted band so it stays readable.
    private var headerBand: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                categoryTag
                Text(mod.name)
                    .font(.title2.weight(.bold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)   // wrap long names
                HStack(spacing: 6) {
                    Text(String(format: vm.L(L10n.Mods.versionPrefix), vm.displayVersion(for: mod)))
                    if !mod.isGroup, !mod.author.isEmpty, mod.author != "Unknown" {
                        Text("•")
                        Text(mod.author)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                let link = vm.nexusLink(for: mod)
                if !link.isEmpty {
                    HStack(spacing: 16) {
                        linkButton(icon: "link", label: vm.L(L10n.Mods.nexusOpenPage), url: link)
                        linkButton(icon: "ladybug", label: vm.L(L10n.Mods.detailBugs), url: link + "?tab=bugs")
                    }
                }
            }
            Spacer(minLength: 8)
            metadataColumn
        }
        .frame(maxWidth: 700, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor.opacity(0.06))
        .overlay(alignment: .bottom) { Divider() }
    }

    /// The mod's category as a colored chip — the Nexus category when known,
    /// otherwise the inferred offline type tag (same resolution as the list).
    @ViewBuilder
    private var categoryTag: some View {
        if let cat = vm.category(for: mod) {
            HStack(spacing: 5) {
                Circle().fill(cat.color).frame(width: 7, height: 7)
                Text(cat.localizedName(vm.L)).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(cat.color.opacity(0.18))
            .clipShape(Capsule())
        } else {
            HStack(spacing: 5) {
                Image(systemName: "tag.fill").font(.system(size: 9))
                Text(vm.L(L10n.ModTag.key(for: vm.inferredTagKey(for: mod)))).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
        }
    }

    /// Metadata stacked vertically on the right of the header band (last update,
    /// install date, languages) — one under another. Empty when nothing's known.
    @ViewBuilder
    private var metadataColumn: some View {
        let updated = vm.nexusLastUpdated(for: mod)
        let installed = vm.installedDate(for: mod)
        let langs = mod.languages
        if updated != nil || installed != nil || !langs.isEmpty {
            VStack(alignment: .trailing, spacing: 8) {
                if let updated {
                    metaLine(icon: "clock.arrow.circlepath",
                             label: vm.L(L10n.Mods.detailUpdated),
                             text: updated.formatted(date: .abbreviated, time: .omitted))
                }
                if let installed {
                    metaLine(icon: "tray.and.arrow.down",
                             label: vm.L(L10n.Mods.detailInstalled),
                             text: installed.formatted(date: .abbreviated, time: .omitted))
                }
                if !langs.isEmpty {
                    metaLine(icon: "globe",
                             label: vm.L(L10n.Mods.detailLanguages),
                             text: langs.map { $0.uppercased() }.joined(separator: " "))
                }
            }
            .frame(maxWidth: 210, alignment: .trailing)
        }
    }

    private func metaLine(icon: String, label: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.secondary)
            VStack(alignment: .trailing, spacing: 1) {
                Text(label).font(.system(size: 9)).foregroundStyle(.secondary.opacity(0.75))
                Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
        }
    }

    private func linkButton(icon: String, label: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.footnote.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .pointingHandCursor()
    }

    // MARK: Pack contents (children of a group)

    @ViewBuilder
    private var packContentsSection: some View {
        if let children = mod.children, !children.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: vm.L(L10n.Mods.detailPackContents), children.count))
                    .font(.headline)
                VStack(spacing: 6) {
                    ForEach(children) { child in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(child.isEnabled ? Color.green : Color.secondary.opacity(0.35))
                                .frame(width: 7, height: 7)
                            Text(child.name).font(.system(size: 13))
                            Spacer()
                            if !child.version.isEmpty, child.version != "Unknown" {
                                Text("v\(child.version)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: Settings (category + Nexus id) — migrated from `ModDetailsPopover`

    /// Grouped, boxed section sitting between the header and the read-only
    /// content tabs: HIG guidance keeps interactive controls (pickers, text
    /// fields) out of the scrolling Description/Changelog/Dependencies tabs,
    /// so both editors live here instead, always visible regardless of tab.
    @ViewBuilder
    private var settingsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                categorySection
                Divider()
                nexusSection
            }
            .padding(.vertical, 4)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.L(L10n.Mods.categoryLabel))
                .font(.headline)
            categoryPicker
            Text(vm.L(L10n.Mods.categoryEditHint))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Dropdown bound to the mod's own effective category (never the
    /// pack→child fallback used elsewhere for content resolution). Selecting
    /// "Automatic" clears any user override; selecting a category pins it.
    private var categoryPicker: some View {
        let overrideId = vm.customCategoryId(for: mod)
        return Picker("", selection: Binding<Int?>(
            get: { overrideId },
            set: { newValue in vm.setCustomCategory(for: mod, categoryId: newValue) }
        )) {
            Text(vm.L(L10n.Mods.categoryAutomatic)).tag(Int?.none)
            ForEach(NexusCategory.all) { cat in
                Text(cat.localizedName(vm.L)).tag(Int?.some(cat.id))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Nexus-id editor + fetch status. The header above already renders a
    /// "View on Nexus" link, so unlike the old popover this section skips the
    /// open-link button and the raw URL text — it only owns the id itself.
    private var nexusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.L(L10n.Mods.nexusSection))
                .font(.headline)
            HStack(spacing: 8) {
                Text(vm.L(L10n.Mods.nexusModId))
                    .font(.system(size: 11, weight: .medium))
                TextField("191", text: $nexusIdDraft)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .onSubmit { commitDraft() }
                Button(vm.L(L10n.Mods.nexusSave)) { commitDraft() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isValidDraft)
                if vm.nexusCustomModIds[mod.folderName] != nil {
                    Button(vm.L(L10n.Mods.nexusReset)) { resetDraft() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundColor(.red)
                }
            }
            Text(vm.L(L10n.Mods.nexusModIdHint))
                .font(.caption)
                .foregroundStyle(.secondary)
            fetchStatusRow
        }
    }

    /// Compact status row shown below the mod id editor. Reflects the on-demand
    /// metadata fetch triggered by `commitDraft`: spinner while loading,
    /// category + latest version on success, or a localized error message.
    @ViewBuilder
    private var fetchStatusRow: some View {
        switch fetchStatus {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(vm.L(L10n.Mods.nexusFetching))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        case .success(let catName, let latest):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                    Text(vm.L(L10n.Mods.nexusFetchSuccess))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                if let cat = catName {
                    Text(String(format: vm.L(L10n.Mods.nexusFetchedCategory), cat))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.85))
                }
                if let v = latest {
                    Text(String(format: vm.L(L10n.Mods.nexusLatestVersion), v))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.85))
                }
            }
        case .noApiKey:
            Text(vm.L(L10n.Mods.nexusNoApiKey))
                .font(.system(size: 10))
                .foregroundColor(.orange)
        case .failed(let msg):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 10))
                Text(String(format: vm.L(L10n.Mods.nexusFetchFailed), msg))
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
        }
    }

    /// A Nexus mod id draft is valid when empty (clears the override) or a
    /// positive integer. Shared by `isValidDraft` (disables the Save button)
    /// and `commitDraft` (guards the actual save) so they can't disagree.
    private func isValidNexusIdDraft(_ trimmed: String) -> Bool {
        trimmed.isEmpty || (Int(trimmed).map { $0 > 0 } ?? false)
    }

    private var isValidDraft: Bool {
        isValidNexusIdDraft(nexusIdDraft.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func seedDraft() {
        // `resolved…`, not `effective…`: a pack header carries no id of its own
        // (it isn't a mod), so `effectiveNexusModId` returned "" and the field
        // looked empty even though the pack's children declare an id — which
        // the rest of this pane happily uses, since the header link and the
        // description both resolve through the children. The field was the only
        // place showing nothing.
        nexusIdDraft = vm.resolvedNexusModId(for: mod)
    }

    private func commitDraft() {
        let trimmed = nexusIdDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidNexusIdDraft(trimmed) else { return }
        vm.setCustomNexusModId(for: mod, modId: trimmed.isEmpty ? nil : trimmed)
        nexusIdDraft = vm.resolvedNexusModId(for: mod)
        // The description, changelog and dependency pane all key off the mod
        // id, but they were only ever loaded when navigating *into* the pane
        // (`viewingModDetail.didSet`). Entering an id therefore fetched the
        // metadata below while the description kept showing the local manifest
        // text — the one thing the user was trying to fix. Reload it here.
        vm.loadModDetail(for: mod)
        // When a mod id is saved, fetch its metadata (category + latest
        // version) from Nexus so the badge and update detection pick it up
        // immediately. Clearing the id resets the status to idle.
        let effectiveId = vm.resolvedNexusModId(for: mod)
        guard !effectiveId.isEmpty else { fetchStatus = .idle; return }
        fetchStatus = .loading
        vm.fetchMetadata(forNexusModId: effectiveId) { result in
            switch result {
            case .success(let version, let catId, _):
                let catName: String? = catId.flatMap { NexusCategory.from(id: $0) }
                    .map { $0.localizedName(vm.L) }
                fetchStatus = .success(categoryName: catName, latestVersion: version)
            case .noApiKey:
                fetchStatus = .noApiKey
            case .rateLimited(let retry):
                fetchStatus = .failed("rate limited (\(Int(retry))s)")
            case .error(let msg):
                fetchStatus = .failed(msg)
            }
        }
    }

    private func resetDraft() {
        vm.setCustomNexusModId(for: mod, modId: nil)
        nexusIdDraft = vm.resolvedNexusModId(for: mod)
        // Same reason as in `commitDraft`: dropping a custom id changes which
        // Nexus mod this pane describes, so the description has to follow.
        vm.loadModDetail(for: mod)
        fetchStatus = .idle
    }

    // MARK: Dependencies

    /// Transitive dependency tree (see `DependencyTreeView`), replacing SP2's
    /// flat list. Empty/loaded states are handled inside the tree view.
    @ViewBuilder
    private var dependenciesSection: some View {
        DependencyTreeView(vm: vm, mod: mod)
    }

    // MARK: Error history

    /// Errors and warnings this mod logged, per version — so a version can be
    /// compared against the one before it. Hidden entirely when the mod has
    /// never logged anything, which is the normal case.
    @ViewBuilder
    private var errorHistorySection: some View {
        let records = vm.modErrorHistory.history(for: mod.folderName)
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(vm.L(L10n.Mods.errorHistory))
                    .font(.system(size: 13, weight: .semibold))
                Text(vm.L(L10n.Mods.errorHistoryHint))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(records, id: \.version) { record in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(record.version)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                            // The mod's current version, for context: an old
                            // version's tally isn't what the player runs today.
                            if record.version == mod.version {
                                Text(vm.L(L10n.Mods.errorHistoryCurrent))
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(3)
                            }
                            Spacer()
                            if record.errorCount > 0 {
                                Label("\(record.errorCount)", systemImage: "xmark.octagon")
                                    .font(.system(size: 10))
                                    .foregroundColor(.red)
                            }
                            if record.warningCount > 0 {
                                Label("\(record.warningCount)", systemImage: "exclamationmark.triangle")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            }
                        }
                        Text(record.lastSeen, style: .date)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        ForEach(record.samples, id: \.self) { sample in
                            Text(sample)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: Tab content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case 2:
            dependenciesSection
        case 1:
            blocksView(isChangelog: true)
        default:
            // Description tab: pack contents (for a pack) + the category /
            // Nexus-id editors + the rendered description.
            VStack(alignment: .leading, spacing: 16) {
                if mod.isGroup { packContentsSection }
                settingsSection
                errorHistorySection
                blocksView(isChangelog: false)
            }
        }
    }

    /// Renders the description or changelog blocks with loading / empty states.
    @ViewBuilder
    private func blocksView(isChangelog: Bool) -> some View {
        if let state = vm.modDetailState {
            let blocks = isChangelog ? state.changelog : state.description
            if blocks.isEmpty {
                if state.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    // Content genuinely absent (not loading): the mod has no
                    // description / no changelog for this version. Connectivity
                    // isn't tracked here, so a neutral per-tab message is more
                    // honest than an "offline" claim that would also fire for a
                    // perfectly online mod that simply ships no changelog.
                    ContentUnavailableView(
                        vm.L(isChangelog ? L10n.Mods.detailNoChangelog : L10n.Mods.detailNoDescription),
                        systemImage: "doc.plaintext"
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
