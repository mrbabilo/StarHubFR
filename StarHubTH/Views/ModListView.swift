import SwiftUI

/// Scope filter for the mods list.
enum ModFilter: String, CaseIterable, Identifiable {
    case all, enabled, disabled, issues
    var id: String { rawValue }
}

/// Three-state French-translation filter: off (all mods), only mods that ship
/// an `fr` i18n file, or only mods that don't. Matches `ModItem.languages`
/// (lowercased codes from the mod's `i18n/` folder).
enum FrenchTranslationScope: Equatable {
    case off
    case available   // ships an i18n/fr.json
    case missing     // no i18n/fr.json
}

/// Scope for the category-filter menu: show everything, scope to one Nexus
/// category, or scope to mods with no category assigned. A single enum
/// (rather than `NexusCategory?` plus a separate boolean) keeps these three
/// states mutually exclusive by construction.
enum CategoryScope: Equatable {
    case all
    case category(NexusCategory)
    case inferredTag(String)   // stable inferTag key, for mods with no Nexus category
    case uncategorized         // mods with no Nexus category whose inferred tag is "Other"
}

/// Sort order for the mods list. `.name` matches `vm.mods`'s existing
/// alphabetical order (so no extra sort is needed for it); `.activationOrder`
/// sorts by `vm.modActivationTimestamps`, most recent first; `.installDate`
/// sorts by `installedFileDate` (folder mod date), most recent first.
enum ModSortOrder: String, CaseIterable, Identifiable {
    case name, nameDescending, activationOrder, installDate, author, version
    var id: String { rawValue }
}

/// A single slot in the pagination footer: either a numbered page button or
/// an ellipsis gap. Using an enum (instead of a sentinel like `-1`) makes it
/// impossible for an ellipsis to collide with a page number identity, which
/// would crash SwiftUI if duplicate `id` values appeared in `ForEach`.
private enum PageSlot {
    case page(Int)
    case ellipsis
}

struct ModListView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var searchText = ""
    @State private var selectedFilter: ModFilter = .all
    /// Category-filter scope: show everything, scope to one Nexus category,
    /// or scope to mods with no category assigned. `.category` only affects
    /// mods whose category was fetched during the last Nexus check or set
    /// manually; `.uncategorized` is the counterpart for the rest.
    @State private var selectedCategory: CategoryScope = .all
    @State private var selectedSort: ModSortOrder = .name
    /// Scopes the list to mods (or packs with at least one qualifying child)
    /// that have a `config.json`. Combines with the category/scope filters —
    /// AND semantics, same as every other filter in `filteredMods`.
    @State private var configOnlyFilter: Bool = false
    /// Three-state French-translation filter (see `FrenchTranslationScope`).
    /// Combines with every other filter — AND semantics.
    @State private var frenchTranslationFilter: FrenchTranslationScope = .off
    /// Current page for the paginated mod list (1-based). Reset to 1 whenever
    /// the search text, scope filter, or category filter changes.
    @State private var currentPage: Int = 1
    /// Number of mods rendered per page. Tuned so the list stays responsive
    /// even with several hundred installed mods.
    private let pageSize: Int = 15
    @State private var showInstallSheet = false
    /// Drives the confirmation dialog when the user picks "Enable All" or
    /// "Disable All" from the bulk-actions menu. `true` = enabling, `false`
    /// = disabling — kept as a single optional so the dialog binds cleanly.
    @State private var bulkToggleTarget: Bool? = nil

    /// Whether `mod` itself satisfies `predicate`, or — for a group — any of
    /// its children do. Standalone mods just apply the predicate directly.
    /// The single "does this row match X" test shared by search and the
    /// issues filter, so the two can't independently drift out of sync (a
    /// group's own `dependencies`/`uniqueId` are empty, so checking the
    /// group itself before its children is always safe and often a no-op).
    private func matchesSelfOrAnyChild(_ mod: ModItem, _ predicate: (ModItem) -> Bool) -> Bool {
        if predicate(mod) { return true }
        if mod.isGroup, let children = mod.children {
            return children.contains(where: predicate)
        }
        return false
    }

    /// Whether `mod` is enabled and has at least one problematic required
    /// dependency (missing entirely, or installed but disabled). A disabled
    /// mod isn't currently relying on its dependencies, so it's excluded
    /// even if one is missing/disabled. Shared by `modsWithIssues` and
    /// `scopeCounts` so their notion of "has issues" can't drift apart.
    private func hasIssues(_ mod: ModItem) -> Bool {
        mod.isEnabled &&
            (!vm.getMissingDependencies(for: mod).isEmpty
                || !vm.getDisabledDependencies(for: mod).isEmpty)
    }

    var filteredMods: [ModItem] {
        vm.mods
            .filter { mod in
                searchText.isEmpty || matchesSelfOrAnyChild(mod) {
                    $0.name.localizedCaseInsensitiveContains(searchText) || $0.uniqueId.localizedCaseInsensitiveContains(searchText)
                }
            }
            .filter { mod in
                switch selectedCategory {
                case .all:
                    return true
                case .category(let cat):
                    // `vm.category(for:)` already resolves a group to its
                    // dominant child category, so this agrees with the badge
                    // shown on the group's own row by construction.
                    return vm.category(for: mod)?.id == cat.id
                case .inferredTag(let tag):
                    return vm.category(for: mod) == nil && vm.inferredTagKey(for: mod) == tag
                case .uncategorized:
                    // Same reasoning: `vm.category(for:)` returns nil for a
                    // group exactly when none of its children have a known
                    // category, matching what its badge (absence) shows.
                    return vm.category(for: mod) == nil && vm.inferredTagKey(for: mod) == "Other"
                }
            }
            .filter { mod in
                !configOnlyFilter || matchesSelfOrAnyChild(mod) { $0.hasConfigFile }
            }
            .filter { mod in
                switch frenchTranslationFilter {
                case .off:
                    return true
                case .available:
                    // A group matches if any child ships an fr translation.
                    return matchesSelfOrAnyChild(mod) { $0.languages.contains("fr") }
                case .missing:
                    return !matchesSelfOrAnyChild(mod) { $0.languages.contains("fr") }
                }
            }
            .sorted { lhs, rhs in
                switch selectedSort {
                case .name:
                    // `vm.mods` is already alphabetical (see `scanMods()`),
                    // and `.sorted` is stable, so this is a no-op ordering
                    // pass — kept as an explicit case so the switch stays
                    // exhaustive and self-documenting.
                    return false
                case .activationOrder:
                    let lhsDate = vm.modActivationTimestamps[lhs.folderName]
                    let rhsDate = vm.modActivationTimestamps[rhs.folderName]
                    switch (lhsDate, rhsDate) {
                    case (let l?, let r?):
                        return l > r
                    case (.some, nil):
                        return true
                    case (nil, .some):
                        return false
                    case (nil, nil):
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                case .installDate:
                    let lhsDate = effectiveInstallDate(for: lhs)
                    let rhsDate = effectiveInstallDate(for: rhs)
                    switch (lhsDate, rhsDate) {
                    case (let l?, let r?):
                        return l > r
                    case (.some, nil):
                        return true
                    case (nil, .some):
                        return false
                    case (nil, nil):
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                case .nameDescending:
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
                case .author:
                    let authorOrder = lhs.author.localizedCaseInsensitiveCompare(rhs.author)
                    if authorOrder != .orderedSame { return authorOrder == .orderedAscending }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                case .version:
                    let versionOrder = NexusUpdateChecker.compare(lhs.version, rhs.version)
                    if versionOrder != .orderedSame { return versionOrder == .orderedDescending }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
    }

    func activeMods(from filtered: [ModItem]) -> [ModItem] { filtered.filter { $0.isEnabled } }
    func inactiveMods(from filtered: [ModItem]) -> [ModItem] { filtered.filter { !$0.isEnabled } }

    /// Returns the mod's own `installedFileDate`, or — for a pack header
    /// whose own date is nil — the most recent child's date. Used by the
    /// `.installDate` sort so packs sort by their newest member.
    private func effectiveInstallDate(for mod: ModItem) -> Date? {
        if let date = mod.installedFileDate { return date }
        guard mod.isGroup, let children = mod.children, !children.isEmpty else { return nil }
        return children.compactMap { $0.installedFileDate }.max()
    }

    /// Enabled mods (or packs containing an enabled child) with at least one
    /// problematic required dependency — either completely missing or
    /// installed-but-disabled. A disabled mod isn't currently relying on its
    /// dependencies, so it's excluded even if one is missing/disabled. Packs
    /// (groups) appear if any enabled child matches.
    func modsWithIssues(from filtered: [ModItem]) -> [ModItem] {
        filtered.filter { matchesSelfOrAnyChild($0, hasIssues) }
    }

    /// The full ordered list of mods that should be displayed under the current
    /// scope (search + category + enabled/disabled filter). Pagination slices
    /// this list; the scope section headers (Enabled/Disabled) are derived from
    /// each page's slice.
    ///
    /// Takes `filtered` (rather than re-deriving it) so callers that already
    /// computed it once per render don't trigger the search/category/sort
    /// pass again.
    private func displayMods(from filtered: [ModItem]) -> [ModItem] {
        switch selectedFilter {
        case .all:      return activeMods(from: filtered) + inactiveMods(from: filtered)
        case .enabled:  return activeMods(from: filtered)
        case .disabled: return inactiveMods(from: filtered)
        case .issues:   return modsWithIssues(from: filtered)
        }
    }

    private func totalPages(for mods: [ModItem]) -> Int {
        guard !mods.isEmpty else { return 1 }
        return Int(ceil(Double(mods.count) / Double(pageSize)))
    }

    /// The clamped page used for both the slice and the footer, so they can
    /// never disagree even during the transient render before `onChange`
    /// resets `currentPage`.
    private func effectivePage(totalPages: Int) -> Int {
        min(max(1, currentPage), totalPages)
    }

    /// Mods on the current page. Always clamped so a shrinking result set
    /// (e.g. typing more search characters) never produces an out-of-range
    /// index.
    private func pageMods(from mods: [ModItem], page: Int) -> [ModItem] {
        let total = mods.count
        guard total > 0 else { return [] }
        let start = (page - 1) * pageSize
        let end = min(start + pageSize, total)
        return Array(mods[start..<end])
    }

    /// Categories actually present among the currently installed mods, sorted
    /// alphabetically by localized name. Drives the category-picker menu so the
    /// user never sees an empty scope. Computed from the *effective* category
    /// of every mod (manual override wins over the API-fetched category), so
    /// user-categorized mods appear in the picker as soon as they're pinned.
    private var availableCategories: [(category: NexusCategory, count: Int)] {
        var counts: [Int: Int] = [:]
        // Counts must be derived the exact same way the `.category` filter
        // branch resolves a mod (`vm.category(for: mod)` on the top-level
        // mod, which already resolves a group to its dominant child
        // category) — counting each child's own category individually (as
        // this used to) could show a non-zero count for a category that,
        // once selected, filters nothing in because it's a group's minority
        // category rather than its dominant one.
        for mod in vm.mods {
            if let cid = vm.category(for: mod)?.id { counts[cid, default: 0] += 1 }
        }
        return NexusCategory.all
            .filter { counts[$0.id] != nil }
            .map { ($0, counts[$0.id] ?? 0) }
            .sorted { $0.category.localizedName(vm.L)
                .localizedCaseInsensitiveCompare($1.category.localizedName(vm.L)) == .orderedAscending }
    }

    /// (tag key, localized label, count) for top-level mods with no Nexus
    /// category and a non-"Other" inferred tag — the offline fallback buckets.
    private var inferredTagBuckets: [(tag: String, label: String, count: Int)] {
        var counts: [String: Int] = [:]
        for mod in vm.mods where vm.category(for: mod) == nil {
            let tag = vm.inferredTagKey(for: mod)
            if tag != "Other" { counts[tag, default: 0] += 1 }
        }
        return counts.map { (tag: $0.key, label: vm.L(L10n.ModTag.key(for: $0.key)), count: $0.value) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Count of top-level mods (standalone mods + whole packs) with no
    /// category assigned AND an inferred tag of "Other" — matching the
    /// `.uncategorized` filter case above (mods with a more specific inferred
    /// tag are counted in `inferredTagBuckets` instead). Drives the
    /// "No Category (N)" menu entry and its visibility.
    private var uncategorizedCount: Int {
        vm.mods.filter { vm.category(for: $0) == nil && vm.inferredTagKey(for: $0) == "Other" }.count
    }

    /// Precomputed counts for all four scope filters, derived in a single pass
    /// over `filtered`. Avoids recomputing `modsWithIssues` (which does a
    /// per-mod dependency scan) every time the Picker label is evaluated.
    /// `issues` mirrors `modsWithIssues`'s enabled-only rule (see its doc).
    private func scopeCounts(for filtered: [ModItem]) -> (all: Int, enabled: Int, disabled: Int, issues: Int) {
        var enabled = 0, disabled = 0, issues = 0
        for mod in filtered {
            if mod.isEnabled { enabled += 1 } else { disabled += 1 }
            if matchesSelfOrAnyChild(mod, hasIssues) { issues += 1 }
        }
        return (filtered.count, enabled, disabled, issues)
    }

    var body: some View {
        // Compute the expensive derived data once per render instead of
        // re-evaluating the search/category/sort pass (and everything
        // downstream of it) on every Picker label and list access.
        let filtered = filteredMods
        let counts = scopeCounts(for: filtered)
        let categories = availableCategories
        let uncatCount = uncategorizedCount
        let tagBuckets = inferredTagBuckets
        let display = displayMods(from: filtered)
        let pages = totalPages(for: display)
        let page = effectivePage(totalPages: pages)
        let paged = pageMods(from: display, page: page)
        VStack(spacing: 0) {

            // ── Sticky header ────────────────────────────────────────────
            // The toolbar (scope picker + filters + sort) stays fixed above
            // the scrolling list, mirroring LogsView's sticky header layout.
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                // Primary row: scope picker (left) + primary action (right).
                // Keeps the most-used navigation and the key CTA at the
                // same visual priority, above the secondary filters.
                HStack {
                    Picker("", selection: $selectedFilter) {
                        Text("\(vm.L(L10n.Mods.filterAll)) (\(counts.all))")
                            .tag(ModFilter.all)
                        Text("\(vm.L(L10n.Mods.enabled)) (\(counts.enabled))")
                            .tag(ModFilter.enabled)
                        Text("\(vm.L(L10n.Mods.disabled)) (\(counts.disabled))")
                            .tag(ModFilter.disabled)
                        Label("\(vm.L(L10n.Mods.filterIssues)) (\(counts.issues))",
                              systemImage: "exclamationmark.triangle")
                            .tag(ModFilter.issues)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 480)

                    Spacer()

                    // Bulk enable/disable all mods at once. Disabled when
                    // there is nothing to act on (empty list, or every mod
                    // is already in the target state), or while a bulk
                    // toggle operation is already in flight.
                    bulkToggleMenu
                        .disabled(vm.mods.isEmpty || vm.bulkToggleProgress != nil)

                    Button {
                        showInstallSheet = true
                    } label: {
                        Label(vm.L(L10n.ModInstall.installButton), systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Secondary row: filters and sort, grouped as chips.
                // Wraps the set of filter controls in a single HStack so
                // they read as one visual unit ("refine the list"),
                // separate from the primary scope/actions above.
                HStack(spacing: 6) {
                    sortPicker

                    Divider()
                        .frame(height: 16)

                    configFilterToggle

                    Divider()
                        .frame(height: 16)

                    frenchTranslationPicker

                    categoryPicker(categories: categories, uncatCount: uncatCount, tagBuckets: tagBuckets)
                        .disabled(categories.isEmpty && uncatCount == 0 && tagBuckets.isEmpty)
                        .help(categories.isEmpty && uncatCount == 0 && tagBuckets.isEmpty
                              ? vm.L(L10n.Mods.categoryFilterEmptyHint)
                              : vm.L(L10n.Mods.categoryFilterHint))

                    Spacer()

                    if categories.isEmpty && uncatCount == 0 && tagBuckets.isEmpty {
                        Text(vm.L(L10n.Mods.categoryFilterEmptyHint))
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary.opacity(AppDesign.Opacity.secondary))
                    }

                    // Which mod profile is currently applied (read-only hint).
                    if let profile = vm.activeProfile {
                        HStack(spacing: 5) {
                            Image(systemName: "person.crop.circle")
                                .font(AppDesign.Font.footnote)
                            Text(String(format: vm.L(L10n.Profiles.activeLabel), profile.name))
                                .font(AppDesign.Font.footnote(.medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                        .help(String(format: vm.L(L10n.Profiles.activeLabel), profile.name))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // ── Scrollable list ──────────────────────────────────────────
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.xxl) {
                    if filtered.isEmpty {
                        if vm.mods.isEmpty {
                            // Première utilisation : zone de drop XXL
                            EmptyStateDropZone(vm: vm, onInstall: { showInstallSheet = true })
                                .padding(.top, 40)
                        } else {
                            // Recherche sans résultat
                            VStack(spacing: AppDesign.Spacing.lg) {
                                Image(systemName: "puzzlepiece.extension")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary.opacity(AppDesign.Opacity.disabled))
                                Text(String(format: vm.L(L10n.Mods.noModFound), searchText))
                                    .multilineTextAlignment(.center)
                                    .font(AppDesign.Font.rowTitle)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }
                    } else if display.isEmpty {
                        // Scope eliminated every mod (e.g. "Disabled" picked but
                        // everything is enabled, or "Issues" with no problems).
                        if selectedFilter == .issues { noIssuesMessage } else { emptyScopeMessage }
                    } else {
                        // Render the current page only. For the "All" scope the
                        // page is split into Enabled/Disabled sections so the
                        // visual grouping is preserved.
                        switch selectedFilter {
                        case .all:
                            let pageActive = paged.filter { $0.isEnabled }
                            let pageInactive = paged.filter { !$0.isEnabled }
                            if !pageActive.isEmpty {
                                ModSectionGroup(title: vm.L(L10n.Mods.enabled), mods: pageActive, vm: vm)
                            }
                            if !pageInactive.isEmpty {
                                ModSectionGroup(title: vm.L(L10n.Mods.disabled), mods: pageInactive, vm: vm)
                            }
                        case .enabled:
                            ModSectionGroup(title: vm.L(L10n.Mods.enabled), mods: paged, vm: vm)
                        case .disabled:
                            ModSectionGroup(title: vm.L(L10n.Mods.disabled), mods: paged, vm: vm)
                        case .issues:
                            ModSectionGroup(title: vm.L(L10n.Mods.filterIssues), mods: paged, vm: vm)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, AppDesign.Spacing.lg)
            }

            // ── Sticky pagination footer ─────────────────────────────────
            // Stays pinned at the bottom of the view while the list scrolls,
            // mirroring LogsView's sticky status bar.
            if !filtered.isEmpty && !display.isEmpty && pages > 1 {
                Divider()
                paginationFooter(total: display.count, shown: paged.count, page: page, totalPages: pages)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            if let prog = vm.bulkToggleProgress, prog.total > 0 {
                bulkToggleOverlay(done: prog.done, total: prog.total)
            }
        }
        .searchable(text: $searchText, prompt: Text(vm.L(L10n.Mods.searchMods)))
        .onChange(of: searchText)       { _, _ in currentPage = 1 }
        .onChange(of: selectedFilter)   { _, _ in currentPage = 1 }
        .onChange(of: selectedCategory) { _, _ in currentPage = 1 }
        .onChange(of: configOnlyFilter) { _, _ in currentPage = 1 }
        .onChange(of: frenchTranslationFilter) { _, _ in currentPage = 1 }
        .onChange(of: vm.mods.count)    { _, _ in currentPage = 1 }
        // Clicking a mod name in the logs must land on that mod, not on the full
        // list. `selectedModID` alone only tints the row — with filters and
        // pagination the mod may not even be on the visible page — so scope the
        // list to it and clear anything that could filter it out.
        .onReceive(NotificationCenter.default.publisher(for: .jumpToMod)) { note in
            guard let modName = note.object as? String else { return }
            // Prefer the resolved mod's own name: SMAPI logs a display name that
            // may differ slightly from the manifest, and searchText matches on
            // name/uniqueId.
            let resolved = vm.mods
                .flatMap { m -> [ModItem] in m.isGroup ? (m.children ?? []) : [m] }
                .first { $0.name.localizedCaseInsensitiveContains(modName) }
            searchText = resolved?.name ?? modName
            selectedFilter = .all
            selectedCategory = .all
            configOnlyFilter = false
            frenchTranslationFilter = .off
            currentPage = 1
        }
        .sheet(isPresented: $showInstallSheet) {
            ModInstallView(vm: vm, isPresented: $showInstallSheet)
        }
        .confirmationDialog(
            bulkToggleTarget == true
                ? vm.L(L10n.Mods.enableAllConfirm)
                : vm.L(L10n.Mods.disableAllConfirm),
            isPresented: Binding(
                get: { bulkToggleTarget != nil },
                set: { if !$0 { bulkToggleTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(bulkToggleTarget == true
                   ? vm.L(L10n.Mods.enableAll)
                   : vm.L(L10n.Mods.disableAll),
                   role: .destructive) {
                if let target = bulkToggleTarget {
                    vm.toggleAllMods(enable: target)
                }
                bulkToggleTarget = nil
            }
            Button(vm.L(L10n.Saves.cancel), role: .cancel) {
                bulkToggleTarget = nil
            }
        } message: {
            Text(bulkToggleTarget == true
                 ? vm.L(L10n.Mods.enableAllMessage)
                 : vm.L(L10n.Mods.disableAllMessage))
        }
    }

    /// Placeholder shown when the current scope has no mods to display
    /// (e.g. "Disabled" selected but every mod is enabled).
    private var emptyScopeMessage: some View {
        VStack(spacing: AppDesign.Spacing.md) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(AppDesign.Opacity.disabled))
            Text(vm.L(selectedFilter == .enabled
                      ? L10n.Mods.disabled
                      : L10n.Mods.enabled))
                .font(AppDesign.Font.rowTitle)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    /// Placeholder shown when the "Issues" scope has no problematic mods.
    private var noIssuesMessage: some View {
        VStack(spacing: AppDesign.Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundColor(.green.opacity(0.6))
            Text(vm.L(L10n.Mods.filterIssues))
                .font(AppDesign.Font.rowTitle)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    /// Prev/Next navigation + numbered page buttons shown below the mod list
    /// when the result set spans more than one page. Takes the already-computed
    /// total/shown/page/totalPages from `body` instead of re-deriving them.
    ///
    /// Shows up to 7 page slots with smart ellipsis: first, last, current,
    /// and neighbors — so the user can jump visually without typing.
    private func paginationFooter(total: Int, shown: Int, page: Int, totalPages: Int) -> some View {
        let rangeStart = (page - 1) * pageSize + 1
        let rangeEnd = rangeStart + shown - 1
        return VStack(spacing: AppDesign.Spacing.sm) {
            HStack(spacing: 6) {
                Button {
                    if currentPage > 1 { currentPage -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(currentPage == 1)
                .help(vm.L(L10n.Mods.prevPageHint))

                // Numbered page buttons with ellipsis logic.
                ForEach(Array(pageSlots(current: page, total: totalPages).enumerated()), id: \.offset) { _, slot in
                    switch slot {
                    case .ellipsis:
                        Text("…")
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary.opacity(0.6))
                            .frame(width: 24)
                    case .page(let n):
                        Button {
                            currentPage = n
                        } label: {
                            Text("\(n)")
                                .font(.system(size: 12, weight: n == page ? .semibold : .regular))
                                .foregroundColor(n == page ? .white : .primary)
                                .frame(width: 24, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(n == page ? Color.accentColor : Color.secondary.opacity(0.08))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .pointingHandCursor()
                    }
                }

                Button {
                    if currentPage < totalPages { currentPage += 1 }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(currentPage == totalPages)
                .help(vm.L(L10n.Mods.nextPageHint))
            }

            Text(String(format: vm.L(L10n.Mods.pageShowing), rangeStart, rangeEnd, total))
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(AppDesign.Opacity.secondary))
        }
        .padding(.top, 4)
    }

    /// Builds the list of page-number slots to render. Always includes first,
    /// last, current, and the current's immediate neighbors; collapses the
    /// middle with `.ellipsis` when the total exceeds 7 slots. The enum makes
    /// it impossible for an ellipsis to collide with a page number.
    private func pageSlots(current: Int, total: Int) -> [PageSlot] {
        if total <= 7 {
            return (1...total).map { .page($0) }
        }
        var slots: [PageSlot] = [.page(1)]
        let lower = max(2, current - 1)
        let upper = min(total - 1, current + 1)
        if lower > 2 { slots.append(.ellipsis) }
        slots.append(contentsOf: (lower...upper).map { .page($0) })
        if upper < total - 1 { slots.append(.ellipsis) }
        slots.append(.page(total))
        return slots
    }

    /// Dropdown choosing how the mods list is ordered. `.name` mirrors the
    /// list's default (already-alphabetical) order; `.activationOrder`
    /// sorts by `vm.modActivationTimestamps`; `.installDate` sorts by
    /// `installedFileDate` (folder mod date), most recent first.
    /// `sortItem` shows a checkmark on the currently active option so the
    /// user can see which sort is applied without scanning the chip label.
    @ViewBuilder
    private func sortItem(_ order: ModSortOrder, label: String, icon: String) -> some View {
        let active = selectedSort == order
        Button {
            selectedSort = order
        } label: {
            if active {
                Label(vm.L(label), systemImage: "checkmark")
            } else {
                Label(vm.L(label), systemImage: icon)
            }
        }
    }

    private var sortPicker: some View {
        Menu {
            sortItem(.name, label: L10n.Mods.sortName, icon: "arrow.up.arrow.down")
            sortItem(.nameDescending, label: L10n.Mods.sortNameDescending, icon: "arrow.down.arrow.up")
            sortItem(.activationOrder, label: L10n.Mods.sortActivationOrder, icon: "clock.arrow.circlepath")
            sortItem(.installDate, label: L10n.Mods.sortInstallDate, icon: "calendar")
            sortItem(.author, label: L10n.Mods.sortAuthor, icon: "person.fill")
            sortItem(.version, label: L10n.Mods.sortVersion, icon: "tag")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(AppDesign.Font.footnote)
                Text(sortLabel)
                    .font(AppDesign.Font.caption(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .fill(Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var sortLabel: String {
        switch selectedSort {
        case .name: return vm.L(L10n.Mods.sortName)
        case .nameDescending: return vm.L(L10n.Mods.sortNameDescending)
        case .activationOrder: return vm.L(L10n.Mods.sortActivationOrder)
        case .installDate: return vm.L(L10n.Mods.sortInstallDate)
        case .author: return vm.L(L10n.Mods.sortAuthor)
        case .version: return vm.L(L10n.Mods.sortVersion)
        }
    }

    // MARK: - Config-only filter toggle

    /// Toggle button scoping the list to mods with a `config.json` (see
    /// `configOnlyFilter`). Same visual family as `sortPicker`/
    /// `categoryPicker` (rounded chip, same padding/font), but a plain
    /// toggle rather than a menu — there's only one on/off state, not a
    /// set of choices.
    private var configFilterToggle: some View {
        Button {
            configOnlyFilter.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .font(AppDesign.Font.footnote)
                Text(vm.L(L10n.Mods.configFilterLabel))
                    .font(AppDesign.Font.caption(.medium))
            }
            .foregroundColor(configOnlyFilter ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .fill(configOnlyFilter ? Color.accentColor.opacity(AppDesign.Opacity.medium) : Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(configOnlyFilter ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help(vm.L(L10n.Mods.configFilterLabel))
    }

    // MARK: - French-translation filter picker

    /// Three-state menu scoping the list to mods that ship (or don't ship) an
    /// `i18n/fr.json` translation file. Same chip visual family as the
    /// config-only toggle and the category picker.
    private var frenchTranslationPicker: some View {
        let isActive = frenchTranslationFilter != .off
        let label: String = {
            switch frenchTranslationFilter {
            case .off:       return vm.L(L10n.Mods.frTranslationFilterLabel)
            case .available: return vm.L(L10n.Mods.frTranslationAvailable)
            case .missing:   return vm.L(L10n.Mods.frTranslationMissing)
            }
        }()
        let icon: String = {
            switch frenchTranslationFilter {
            case .off:       return "character.bubble"
            case .available: return "checkmark.bubble"
            case .missing:   return "xmark.bubble"
            }
        }()
        return Menu {
            Button {
                frenchTranslationFilter = .off
            } label: {
                Label(vm.L(L10n.Mods.frTranslationFilterLabel), systemImage: "character.bubble")
            }
            Button {
                frenchTranslationFilter = .available
            } label: {
                Label(vm.L(L10n.Mods.frTranslationAvailable), systemImage: "checkmark.bubble")
            }
            Button {
                frenchTranslationFilter = .missing
            } label: {
                Label(vm.L(L10n.Mods.frTranslationMissing), systemImage: "xmark.bubble")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(AppDesign.Font.footnote)
                Text(label)
                    .font(AppDesign.Font.caption(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(isActive ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .fill(isActive ? Color.accentColor.opacity(AppDesign.Opacity.medium) : Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(vm.L(L10n.Mods.frTranslationFilterLabel))
    }

    /// Full-screen overlay shown while a bulk enable/disable-all operation is
    /// moving mod folders. Blocks all interaction with the list so the user
    /// can't start a conflicting toggle mid-operation. Shows a determinate
    /// progress bar with the current/total count.
    private func bulkToggleOverlay(done: Int, total: Int) -> some View {
        let fraction = total > 0 ? Double(done) / Double(total) : 0
        return ZStack {
            Color.black.opacity(AppDesign.Opacity.strong)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: fraction, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(width: 280)
                    .animation(.easeInOut(duration: 0.2), value: fraction)
                HStack(spacing: 6) {
                    Text(vm.bulkToggleEnabling
                         ? vm.L(L10n.Mods.enablingAllProgress)
                         : vm.L(L10n.Mods.disablingAllProgress))
                        .font(AppDesign.Font.caption(.medium))
                    Text("\(done)/\(total)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(28)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.lg))
            .shadow(color: .black.opacity(AppDesign.Opacity.medium), radius: 12, y: 4)
        }
        .transition(.opacity)
    }

    /// Menu offering to enable or disable every installed mod at once. Each
    /// entry is disabled individually when there is nothing to move in that
    /// direction (all already enabled / all already disabled), so the user
    /// sees why an action isn't available rather than a dead button.
    private var bulkToggleMenu: some View {
        let anyDisabled = vm.mods.contains { !$0.isEnabled }
        let anyEnabled = vm.mods.contains { $0.isEnabled }
        return Menu {
            Button {
                bulkToggleTarget = true
            } label: {
                Label(vm.L(L10n.Mods.enableAll), systemImage: "checkmark.circle")
            }
            .disabled(!anyDisabled)

            Button {
                bulkToggleTarget = false
            } label: {
                Label(vm.L(L10n.Mods.disableAll), systemImage: "xmark.circle")
            }
            .disabled(!anyEnabled)
        } label: {
            Label(vm.L(L10n.Mods.toggleAllHint), systemImage: "power")
                .labelStyle(.iconOnly)
                .font(AppDesign.Font.body)
        }
        .help(vm.L(L10n.Mods.toggleAllHint))
    }

    // MARK: - Category picker

    /// Dropdown listing every category present in the installed mods list.
    /// Selecting one scopes the list to that category; selecting "All" clears
    /// it. Each row shows the category color + localized name + mod count.
    private func categoryPicker(categories: [(category: NexusCategory, count: Int)], uncatCount: Int, tagBuckets: [(tag: String, label: String, count: Int)]) -> some View {
        Menu {
            Button {
                selectedCategory = .all
            } label: {
                Label(vm.L(L10n.Mods.categoryFilterAll), systemImage: "square.grid.2x2")
            }
            if uncatCount > 0 {
                Button {
                    selectedCategory = .uncategorized
                } label: {
                    Label("\(vm.L(L10n.Mods.categoryFilterUncategorized))   (\(uncatCount))", systemImage: "circle.dashed")
                }
            }
            if !categories.isEmpty {
                Divider()
            }
            ForEach(categories, id: \.category.id) { entry in
                Button {
                    selectedCategory = .category(entry.category)
                } label: {
                    // SwiftUI Menus render Button labels as plain text — an
                    // HStack would only show its first child. Concatenating
                    // Text views (or building a single string) keeps both the
                    // icon and the category name visible in the row.
                    Text(entry.category.emoji + " " + entry.category.localizedName(vm.L) + "   (\(entry.count))")
                }
            }
            // Offline fallback: mods with no Nexus category, grouped by their
            // inferred type tag instead of a single "uncategorized" bucket.
            if !tagBuckets.isEmpty {
                Divider()
                ForEach(tagBuckets, id: \.tag) { bucket in
                    Button {
                        selectedCategory = .inferredTag(bucket.tag)
                    } label: {
                        Text("\(bucket.label)   (\(bucket.count))")
                    }
                }
            }
            if selectedCategory != .all {
                Divider()
                Button(role: .destructive) {
                    selectedCategory = .all
                } label: {
                    Label(vm.L(L10n.Mods.categoryFilterClear), systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 6) {
                switch selectedCategory {
                case .all:
                    Image(systemName: "tag")
                        .font(AppDesign.Font.footnote)
                    Text(vm.L(L10n.Mods.categoryFilter))
                        .font(AppDesign.Font.caption(.medium))
                case .category(let cat):
                    Circle()
                        .fill(cat.color)
                        .frame(width: 9, height: 9)
                    Text(cat.localizedName(vm.L))
                        .font(AppDesign.Font.caption(.medium))
                case .inferredTag(let tag):
                    Image(systemName: "tag.circle")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                    Text(vm.L(L10n.ModTag.key(for: tag)))
                        .font(AppDesign.Font.caption(.medium))
                case .uncategorized:
                    Image(systemName: "circle.dashed")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                    Text(vm.L(L10n.Mods.categoryFilterUncategorized))
                        .font(AppDesign.Font.caption(.medium))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .fill(Color.secondary.opacity(AppDesign.Opacity.light))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                    .stroke(Color.secondary.opacity(AppDesign.Opacity.medium), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

}

// MARK: - Section Group
struct ModSectionGroup: View {
    let title: String
    let mods: [ModItem]
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        StandardSection(title: title) {
            VStack(spacing: 0) {
                ForEach(Array(mods.enumerated()), id: \.element.id) { idx, mod in
                    if mod.isGroup, let children = mod.children {
                        ModGroupRow(mod: mod, children: children, vm: vm)
                    } else {
                        ModListRow(mod: mod, vm: vm, isChild: false, isGroupHeader: false, isExpanded: .constant(false))
                    }
                    
                    if idx < mods.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(AppDesign.Opacity.subtle))
                            .frame(height: 1)
                            .padding(.leading, 48)
                            .padding(.vertical, 2)
                    }
                }
            }
            .padding(.vertical, -8)
        }
    }
}

// MARK: - Mod Group Row
struct ModGroupRow: View {
    let mod: ModItem
    let children: [ModItem]
    @ObservedObject var vm: StarHubTHViewModel
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            ModListRow(mod: mod, vm: vm, isChild: false, isGroupHeader: true, isExpanded: $isExpanded)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { cIdx, child in
                        ModListRow(mod: child, vm: vm, isChild: true, isGroupHeader: false, isExpanded: .constant(false))
                        if cIdx < children.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(AppDesign.Opacity.subtle))
                                .frame(height: 1)
                                .padding(.leading, 64)
                                .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Row
struct ModListRow: View {
    let mod: ModItem
    @ObservedObject var vm: StarHubTHViewModel
    @State private var isHovered = false
    var isChild: Bool = false
    var isGroupHeader: Bool = false
    @Binding var isExpanded: Bool
    @State private var localIsOn: Bool?
    /// Drives the confirmation dialog before deleting this row's mod.
    @State private var showDeleteConfirm = false

    private var modRowA11yLabel: String {
        String(
            format: vm.L(L10n.Mods.rowA11yLabel),
            mod.name,
            mod.author,
            String(format: vm.L(L10n.Mods.versionPrefix), mod.version)
        )
    }

    /// The effective enabled state, honoring the optimistic `localIsOn` value
    /// so the visual styling reacts instantly when the toggle is flipped
    /// (before `vm.mods` catches up).
    private var effectiveEnabled: Bool { localIsOn ?? mod.isEnabled }

    /// Compact metadata strip shown under the category/author/version line:
    /// languages (FR highlighted), last-update date, install date. Returns nil
    /// when nothing is known so no empty row is rendered. Uses relative dates
    /// (short form) to keep the line scannable; full dates live in the detail
    /// pane.
    private var rowMetadataLine: AnyView? {
        let updated = vm.nexusLastUpdated(for: mod)
        let installed = mod.installedFileDate
        let langs = mod.languages
        guard updated != nil || installed != nil || !langs.isEmpty else { return nil }
        return AnyView(
            HStack(spacing: 6) {
                if !langs.isEmpty {
                    Image(systemName: "globe")
                        .font(.system(size: 9))
                    Text(langs.map { $0.uppercased() }.joined(separator: " "))
                    // Highlight FR availability so the translation filter is
                    // cross-checkable at a glance on every row.
                    if langs.contains("fr") {
                        Text(vm.L(L10n.Mods.frTranslationAvailable))
                            .foregroundColor(.green.opacity(0.9))
                    }
                    if updated != nil || installed != nil {
                        Text("•")
                            .foregroundColor(.secondary.opacity(AppDesign.Opacity.disabled))
                    }
                }
                if let updated {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9))
                    Text(updated.formatted(.relative(presentation: .named)))
                    if installed != nil {
                        Text("•")
                            .foregroundColor(.secondary.opacity(AppDesign.Opacity.disabled))
                    }
                }
                if let installed {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 9))
                    Text(installed.formatted(date: .abbreviated, time: .omitted))
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {

            // Status accent bar — instant at-a-glance enabled/disabled
            // reading. Green for enabled, muted for disabled. Wider for
            // top-level rows, slimmer for pack children.
            RoundedRectangle(cornerRadius: 2)
                .fill(effectiveEnabled
                      ? Color(red: 0.20, green: 0.65, blue: 0.35)
                      : Color.secondary.opacity(AppDesign.Opacity.strong))
                .frame(width: isChild ? 2.5 : 3.5)

            HStack(spacing: AppDesign.Spacing.md) {
            
            // Chevron space (ensures perfect alignment for all top-level items)
            if !isChild {
                ZStack {
                    if isGroupHeader {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 14, alignment: .center)
            } else {
                // Indent children
                Spacer().frame(width: 32)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mod.name)
                        .font(AppDesign.Font.body(.medium))
                        .foregroundColor(effectiveEnabled ? .primary : .secondary)
                        .lineLimit(1)
                    // Inline status dot — helps the name row itself read as
                    // active/inactive, redundant with the accent bar but
                    // reinforces the state for quick scanning.
                    if !effectiveEnabled && !isChild {
                        Circle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 5, height: 5)
                    }
                }
                
                if mod.name != mod.folderName {
                    Text(mod.folderName)
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                }
                
                if !mod.isGroup {
                    HStack(spacing: 6) {
                        // Category badge — only for mods whose category was
                        // fetched from Nexus or manually pinned. Otherwise
                        // fall back to the offline-inferred type tag.
                        if let cat = vm.category(for: mod) {
                            CategoryBadge(category: cat, L: vm.L)
                        } else {
                            InferredTagBadge(label: vm.L(L10n.ModTag.key(for: vm.inferredTagKey(for: mod))))
                        }
                        Text(mod.author)
                            .font(AppDesign.Font.caption)
                            .foregroundColor(.secondary)
                        Text("•")
                            .foregroundColor(.secondary.opacity(AppDesign.Opacity.disabled))
                        VersionBadge(version: mod.version)
                    }
                } else {
                    // Pack header: show the same metadata (category, author,
                    // version) aggregated from the children, plus the mod count
                    // so the pack size stays visible at a glance.
                    HStack(spacing: 6) {
                        if let cat = vm.category(for: mod) {
                            CategoryBadge(category: cat, L: vm.L)
                        } else {
                            InferredTagBadge(label: vm.L(L10n.ModTag.key(for: vm.inferredTagKey(for: mod))))
                        }
                        Text(vm.displayAuthor(for: mod))
                            .font(AppDesign.Font.caption)
                            .foregroundColor(.secondary)
                        Text("•")
                            .foregroundColor(.secondary.opacity(AppDesign.Opacity.disabled))
                        VersionBadge(version: vm.displayVersion(for: mod))
                        Text("•")
                            .foregroundColor(.secondary.opacity(AppDesign.Opacity.disabled))
                        Text(mod.description)
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary.opacity(0.85))
                    }
                }
                // Compact metadata strip: languages + dates. Only shown when
                // at least one value is known, to avoid an empty row.
                if let metaLine = rowMetadataLine {
                    metaLine
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                let missingDeps = vm.getMissingDependencies(for: mod)
                let disabledDeps = vm.getDisabledDependencies(for: mod)
                if !missingDeps.isEmpty || !disabledDeps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        if !missingDeps.isEmpty {
                            HStack(spacing: AppDesign.Spacing.xs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                // Chaque dépendance manquante est cliquable :
                                // ouvre la recherche Nexus Mods pour ce nom.
                                Text("\(vm.L(L10n.Mods.missingDependenciesPrefix)) ")
                                    .foregroundColor(.secondary)
                                ForEach(Array(missingDeps.enumerated()), id: \.offset) { idx, depId in
                                    HStack(spacing: 2) {
                                        if idx > 0 { Text(",") }
                                        let modName = depId.smapiModName
                                        let author = depId.smapiAuthor
                                        // Au clic, propose deux recherches Nexus :
                                        // par nom du mod (défaut) ou par auteur.
                                        Menu {
                                            Button {
                                                openNexusSearch(for: modName)
                                            } label: {
                                                Label(String(format: vm.L(L10n.Mods.searchNexusByModName), modName),
                                                      systemImage: "magnifyingglass")
                                            }
                                            if !author.isEmpty {
                                                Button {
                                                    openNexusAuthorSearch(for: author)
                                                } label: {
                                                    Label(String(format: vm.L(L10n.Mods.searchNexusByAuthor), author),
                                                          systemImage: "person")
                                                }
                                            }
                                        } label: {
                                            Text(modName)
                                                .underline()
                                                .pointingHandCursor()
                                        }
                                        .menuStyle(.button)
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .foregroundColor(.red)
                        }
                        if !disabledDeps.isEmpty {
                            HStack(spacing: AppDesign.Spacing.xs) {
                                Image(systemName: "exclamationmark.octagon.fill")
                                Text(String(format: vm.L(L10n.Mods.disabledRequiredDeps), disabledDeps.joined(separator: ", ")))
                            }
                            .foregroundColor(.orange)
                        }
                    }
                    .font(AppDesign.Font.footnote)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: 0.85, green: 0.25, blue: 0.20).opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(red: 0.85, green: 0.25, blue: 0.20).opacity(0.2), lineWidth: 0.5)
                    )
                    .padding(.top, 2)
                }
            }

            Spacer()

            // Actions (always visible)
            HStack(spacing: AppDesign.Spacing.md) {
                Button {
                    let url = URL(fileURLWithPath: vm.gameDir)
                        .appendingPathComponent("Mods")
                        .appendingPathComponent(mod.physicalFolderName)
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "folder")
                        .font(AppDesign.Font.rowTitle)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(vm.L(L10n.Mods.openFolder))
                .accessibilityLabel(vm.L(L10n.Mods.openFolder))
                .accessibilityHint(vm.L(L10n.Mods.openFolderA11yHint))
                .pointingHandCursor()

                // Direct config-editor access, mirroring upstream's
                // discoverability: visible only for a standalone mod (never
                // a pack header, which has no config.json of its own) that
                // actually has a config.json. The right-click "Code Editor"
                // context-menu entry stays as an additional entry point.
                if !mod.isGroup && mod.hasConfigFile {
                    Button {
                        vm.editingModConfig = mod
                    } label: {
                        Image(systemName: "gearshape")
                            .font(AppDesign.Font.rowTitle)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(vm.L(L10n.Settings.configCodeEditor))
                    .accessibilityLabel(vm.L(L10n.Settings.configCodeEditor))
                    .accessibilityHint(vm.L(L10n.Settings.configCodeEditorA11yHint))
                    .pointingHandCursor()
                }

                // Direct "open on Nexus" button — visible whenever the mod has
                // an effective Nexus id (manifest-declared or user-assigned).
                let link = vm.nexusLink(for: mod)
                if !link.isEmpty {
                    Button {
                        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                    } label: {
                        Image(systemName: "safari")
                            .font(AppDesign.Font.rowTitle)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(vm.L(L10n.Mods.viewOnNexus))
                    .accessibilityLabel(vm.L(L10n.Mods.viewOnNexus))
                    .accessibilityHint(vm.L(L10n.Mods.viewOnNexusA11yHint))
                    .pointingHandCursor()
                }

                // Info button — always visible so the user can edit the mod's
                // category / Nexus link even when it has no dependencies or
                // pre-existing Nexus URL.
                Button {
                    vm.viewingModDetail = mod
                } label: {
                    Image(systemName: "info.circle")
                        .font(AppDesign.Font.rowTitle)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(vm.L(L10n.Mods.openDetails))
                .accessibilityLabel(vm.L(L10n.Mods.openDetails))
                .accessibilityHint(vm.L(L10n.Mods.openDetailsHint))
                .pointingHandCursor()

                // Delete button — permanently removes the mod (or pack) from
                // disk. Hidden for child rows inside a pack, since the pack
                // header carries the delete action for all children. A
                // confirmation dialog fires before the actual deletion.
                // While the deletion is in flight (folder removal + rescan),
                // a spinner replaces the trash icon on this row.
                if !isChild {
                    if vm.pendingDeleteFolder == mod.folderName {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                            .help(vm.L(L10n.Mods.deleteMod))
                    } else {
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(AppDesign.Font.rowTitle)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(vm.pendingDeleteFolder != nil)
                        .help(vm.L(L10n.Mods.deleteMod))
                        .accessibilityLabel(vm.L(L10n.Mods.deleteMod))
                        .accessibilityHint(vm.L(L10n.Mods.deleteModA11yHint))
                        .pointingHandCursor()
                    }
                }
            }
            .padding(.trailing, 8)


            // macOS Native Switch Toggle
            if !isChild {
                HStack(spacing: AppDesign.Spacing.xs) {
                    // Spinner pendant l'opération de toggle (rename du
                    // dossier dans Mods/ entre X et .X). Disparaît dès
                    // que pendingToggleFolder est remis à nil par le VM.
                    if vm.pendingToggleFolder == mod.folderName {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    }
                    Toggle("", isOn: Binding(
                        get: { localIsOn ?? mod.isEnabled },
                        set: { newValue in
                            localIsOn = newValue
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                if newValue != mod.isEnabled {
                                    // Keep the optimistic value until toggleMod's completion
                                    // confirms vm.mods has actually caught up — clearing it
                                    // eagerly here races the background scanMods() and made
                                    // the switch visibly snap back to its old position.
                                    vm.toggleMod(mod) {
                                        localIsOn = nil
                                    }
                                } else {
                                    localIsOn = nil
                                }
                            }
                        }
                    ))
                        .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.20, green: 0.65, blue: 0.35)))
                        .controlSize(.small)
                        .labelsHidden()
                        .accessibilityLabel(String(format: vm.L(L10n.Mods.toggleA11yLabel), mod.name))
                        .accessibilityHint(vm.L(L10n.Mods.toggleA11yHint))
                        .accessibilityValue(mod.isEnabled ? vm.L(L10n.Mods.enabled) : vm.L(L10n.Mods.disabled))
                }
            } else {
                Toggle("", isOn: .constant(false))
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .controlSize(.small)
                    .labelsHidden()
                    .opacity(0)
            }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            // Dim the content (not the toggle/accent bar) for disabled mods to
            // create visual hierarchy — active mods draw the eye first.
            .opacity(effectiveEnabled ? 1.0 : 0.72)
        }
        .background(
            // Hover: accent-tinted fill for a clearer "interactive" feel.
            isHovered ? Color.accentColor.opacity(0.06) : Color.clear
        )
        .background(
            vm.selectedModID == mod.folderName
                ? Color.accentColor.opacity(0.08)
                : Color.clear
        )
        .cornerRadius(6)
        .overlay(
            // Subtle accent border on hover — polished focus ring.
            RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                .stroke(isHovered ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: effectiveEnabled)
        .onHover { isHovered = $0 }
        // Accessibility : VoiceOver annonce le mod comme un élément unifié
        // avec son nom, auteur, version et état (activé/désactivé).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(modRowA11yLabel)
        .accessibilityValue(mod.isEnabled ? vm.L(L10n.Mods.enabled) : vm.L(L10n.Mods.disabled))
        .accessibilityHint(vm.L(L10n.Mods.openDetailsHint))
        .contextMenu {
            Button(vm.L(L10n.Mods.openInFinder)) {
                let url = URL(fileURLWithPath: vm.gameDir)
                    .appendingPathComponent("Mods")
                    .appendingPathComponent(mod.physicalFolderName)
                NSWorkspace.shared.open(url)
            }
            Button(vm.L(L10n.Settings.configCodeEditor)) {
                vm.editingModConfig = mod
            }
            let effectiveLink = vm.nexusLink(for: mod)
            if !effectiveLink.isEmpty {
                Button(vm.L(L10n.Mods.viewDetailsOnNexus)) {
                    if let url = URL(string: effectiveLink) { NSWorkspace.shared.open(url) }
                }
            }
            if !isChild {
                Divider()
                Button(vm.L(L10n.Mods.deleteMod), role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .confirmationDialog(
            String(format: vm.L(L10n.Mods.deleteConfirmTitle), mod.name),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(vm.L(L10n.Mods.deleteMod), role: .destructive) {
                vm.deleteMod(mod)
            }
            Button(vm.L(L10n.Saves.cancel), role: .cancel) { }
        } message: {
             Text(mod.isGroup
                 ? vm.L(L10n.Mods.deleteConfirmPack)
                 : vm.L(L10n.Mods.deleteConfirmMessage))
        }
    }

    /// Ouvre la recherche Nexus Mods pour une dépendance manquante.
    /// Le terme de recherche utilise le nom lisible (ex. "Content Patcher"
    /// plutôt que l'identifiant unique "Pathoschild.ContentPatcher") pour
    /// exploiter l'indexation par nom de Nexus.
    private func openNexusSearch(for searchTerm: String) {
        let encoded = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchTerm
        if let url = URL(string: "https://www.nexusmods.com/stardewvalley/search/?gsearch=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Ouvre la liste des mods d'un auteur sur Nexus Mods. Le filtre `?author=`
    /// est plus précis qu'une recherche plein texte pour retrouver tous les
    /// mods d'un même auteur.
    private func openNexusAuthorSearch(for author: String) {
        let encoded = author.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? author
        if let url = URL(string: "https://www.nexusmods.com/games/stardewvalley/mods?author=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Category Badge

/// Compact colored pill shown next to a mod's author/version. The dot uses the
/// category's curated color and the text uses the localized name, so the row
/// is scannable by hue even at a glance.
struct CategoryBadge: View {
    let category: NexusCategory
    let L: (String) -> String

    var body: some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Circle()
                .fill(category.color)
                .frame(width: 7, height: 7)
            Text(category.localizedName(L))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(category.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(category.color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(category.color.opacity(0.30), lineWidth: 0.5)
        )
        .help(category.englishName)
    }
}

/// Neutral badge shown in place of `CategoryBadge` when a mod has no Nexus
/// category: displays its offline-inferred type tag (see `ModItem.inferTag`)
/// instead, so uncategorized mods still carry some at-a-glance grouping info.
private struct InferredTagBadge: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(AppDesign.Opacity.medium))
            .foregroundColor(.secondary)
            .clipShape(Capsule())
    }
}

/// Compact monospaced pill for a mod's version number. Replaces the bare
/// `Text("v\(version)")` so the version reads as a distinct, scannable unit
/// rather than blending into the metadata row's bullet-separated text.
private struct VersionBadge: View {
    let version: String
    var body: some View {
        Text("v\(version)")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(AppDesign.Opacity.light))
            )
    }
}
