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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                settingsSection
                Picker("", selection: $selectedTab) {
                    Text(vm.L(L10n.Mods.detailDescription)).tag(0)
                    Text(vm.L(L10n.Mods.detailChangelog)).tag(1)
                    Text(vm.L(L10n.Profiles.dependencies)).tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                content
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .onAppear { seedDraft() }
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
        nexusIdDraft = vm.effectiveNexusModId(for: mod)
    }

    private func commitDraft() {
        let trimmed = nexusIdDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidNexusIdDraft(trimmed) else { return }
        vm.setCustomNexusModId(for: mod, modId: trimmed.isEmpty ? nil : trimmed)
        nexusIdDraft = vm.effectiveNexusModId(for: mod)
        // When a mod id is saved, fetch its metadata (category + latest
        // version) from Nexus so the badge and update detection pick it up
        // immediately. Clearing the id resets the status to idle.
        let effectiveId = vm.effectiveNexusModId(for: mod)
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
        nexusIdDraft = vm.effectiveNexusModId(for: mod)
        fetchStatus = .idle
    }

    // MARK: Dependencies

    /// Required/optional dependency list, migrated from `ModDetailsPopover`.
    /// Its own tab (rather than always-visible) keeps it out of the way for
    /// mods with none, and mirrors the Description/Changelog tabs' pattern of
    /// a single scrollable content area per tab.
    @ViewBuilder
    private var dependenciesSection: some View {
        if mod.dependencies.isEmpty {
            ContentUnavailableView(vm.L(L10n.VM.noDependenciesFound), systemImage: "shippingbox")
                .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(mod.dependencies, id: \.uniqueId) { dep in
                    let targetMod = vm.mods.first { $0.uniqueId.caseInsensitiveCompare(dep.uniqueId) == .orderedSame }
                    let isInstalled = targetMod != nil
                    let isEnabled = targetMod?.isEnabled ?? false
                    HStack {
                        if isEnabled {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 10))
                        } else if isInstalled {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 10))
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red.opacity(0.5))
                                .font(.system(size: 10))
                        }
                        Text(dep.uniqueId)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(isEnabled ? .primary : .secondary)
                        Spacer()
                        if dep.isRequired {
                            Text(vm.L(L10n.Profiles.required))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(4)
                        } else {
                            Text(vm.L(L10n.Profiles.optional))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
    }

    // MARK: Tab content

    @ViewBuilder
    private var content: some View {
        if selectedTab == 2 {
            dependenciesSection
        } else if let state = vm.modDetailState {
            let blocks = selectedTab == 0 ? state.description : state.changelog
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
                        vm.L(selectedTab == 0 ? L10n.Mods.detailNoDescription : L10n.Mods.detailNoChangelog),
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
