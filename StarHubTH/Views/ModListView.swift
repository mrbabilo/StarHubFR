import SwiftUI

/// Scope filter for the mods list.
enum ModFilter: String, CaseIterable, Identifiable {
    case all, enabled, disabled, issues
    var id: String { rawValue }
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
    /// Current page for the paginated mod list (1-based). Reset to 1 whenever
    /// the search text, scope filter, or category filter changes.
    @State private var currentPage: Int = 1
    /// Draft text for the "go to page" field. Kept separate from currentPage
    /// so invalid input (empty / non-numeric) doesn't break the pagination
    /// state; it's only committed on submit.
    @State private var pageJumpDraft: String = ""
    /// Number of mods rendered per page. Tuned so the list stays responsive
    /// even with several hundred installed mods.
    private let pageSize: Int = 15
    @State private var showInstallSheet = false

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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {

                // ── Scope filter ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
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
                        .frame(maxWidth: 520)

                        Spacer()

                        sortPicker

                        configFilterToggle

                        // Category filter (Menu picker). Populated from every
                        // mod's effective category (manual override or API).
                        categoryPicker(categories: categories, uncatCount: uncatCount, tagBuckets: tagBuckets)
                            .disabled(categories.isEmpty && uncatCount == 0 && tagBuckets.isEmpty)
                            .help(categories.isEmpty && uncatCount == 0 && tagBuckets.isEmpty
                                  ? vm.L(L10n.Mods.categoryFilterEmptyHint)
                                  : vm.L(L10n.Mods.categoryFilterHint))

                        Button {
                            showInstallSheet = true
                        } label: {
                            Label(vm.L(L10n.ModInstall.installButton), systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if categories.isEmpty && uncatCount == 0 && tagBuckets.isEmpty {
                        Text(vm.L(L10n.Mods.categoryFilterEmptyHint))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }

                // ── List ──────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 32) {
                    if filtered.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary.opacity(0.5))
                            if vm.mods.isEmpty {
                                Text(vm.L(L10n.Mods.noModsInstalled))
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            } else {
                                Text(String(format: vm.L(L10n.Mods.noModFound), searchText))
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
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

                        if pages > 1 {
                            paginationFooter(total: display.count, shown: paged.count, page: page, totalPages: pages)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .searchable(text: $searchText, prompt: Text(vm.L(L10n.Mods.searchMods)))
        .onChange(of: searchText)       { currentPage = 1 }
        .onChange(of: selectedFilter)   { currentPage = 1 }
        .onChange(of: selectedCategory) { currentPage = 1 }
        .onChange(of: configOnlyFilter) { currentPage = 1 }
        .onChange(of: vm.mods.count)    { currentPage = 1 }
        .sheet(isPresented: $showInstallSheet) {
            ModInstallView(vm: vm)
        }
    }

    /// Placeholder shown when the current scope has no mods to display
    /// (e.g. "Disabled" selected but every mod is enabled).
    private var emptyScopeMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text(vm.L(selectedFilter == .enabled
                      ? L10n.Mods.disabled
                      : L10n.Mods.enabled))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    /// Placeholder shown when the "Issues" scope has no problematic mods.
    private var noIssuesMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundColor(.green.opacity(0.6))
            Text(vm.L(L10n.Mods.filterIssues))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    /// Prev/Next navigation + page indicator + direct page jump shown below
    /// the mod list when the result set spans more than one page. Takes the
    /// already-computed total/shown/page/totalPages from `body` instead of
    /// re-deriving them from `filteredMods` again.
    private func paginationFooter(total: Int, shown: Int, page: Int, totalPages: Int) -> some View {
        let rangeStart = (page - 1) * pageSize + 1
        let rangeEnd = rangeStart + shown - 1
        return HStack(spacing: 16) {
            Button {
                if currentPage > 1 { currentPage -= 1 }
            } label: {
                Label(vm.L(L10n.Mods.pagePrevious), systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(currentPage == 1)

            Spacer()

            VStack(spacing: 2) {
                Text(String(format: vm.L(L10n.Mods.pageIndicator), page, totalPages))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Text(String(format: vm.L(L10n.Mods.pageShowing), rangeStart, rangeEnd, total))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
            }

            Spacer()

            // Direct page jump: small numeric field. Commits on submit/Enter,
            // clamps to [1, totalPages], and ignores non-numeric input.
            HStack(spacing: 4) {
                Text(vm.L(L10n.Mods.pageJumpLabel))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("", text: $pageJumpDraft, prompt: Text("\(currentPage)"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 44)
                    .controlSize(.small)
                    .onSubmit { commitPageJump() }
                    .onChange(of: pageJumpDraft) { oldValue, newValue in
                        // Keep the field numeric-only as the user types.
                        if !newValue.allSatisfy({ $0.isNumber }) && !newValue.isEmpty {
                            pageJumpDraft = oldValue
                        }
                    }
                Text("\(totalPages)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Button {
                if currentPage < totalPages { currentPage += 1 }
            } label: {
                Label(vm.L(L10n.Mods.pageNext), systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(currentPage == totalPages)
        }
        .padding(.top, 4)
    }

    /// Applies the page-jump field: parses the draft, clamps to the valid
    /// range, and clears the field so the placeholder (current page) shows
    /// again.
    private func commitPageJump() {
        let trimmed = pageJumpDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let n = Int(trimmed) else { return }
        let pages = totalPages(for: displayMods(from: filteredMods))
        currentPage = min(max(1, n), pages)
        pageJumpDraft = ""
    }

    /// Dropdown choosing how the mods list is ordered. `.name` mirrors the
    /// list's default (already-alphabetical) order; `.activationOrder`
    /// sorts by `vm.modActivationTimestamps`; `.installDate` sorts by
    /// `installedFileDate` (folder mod date), most recent first.
    private var sortPicker: some View {
        Menu {
            Button {
                selectedSort = .name
            } label: {
                Label(vm.L(L10n.Mods.sortName), systemImage: "textformat")
            }
            Button {
                selectedSort = .nameDescending
            } label: {
                Label(vm.L(L10n.Mods.sortNameDescending), systemImage: "textformat.size.larger")
            }
            Button {
                selectedSort = .activationOrder
            } label: {
                Label(vm.L(L10n.Mods.sortActivationOrder), systemImage: "clock.arrow.circlepath")
            }
            Button {
                selectedSort = .installDate
            } label: {
                Label(vm.L(L10n.Mods.sortInstallDate), systemImage: "calendar.badge.clock")
            }
            Button {
                selectedSort = .author
            } label: {
                Label(vm.L(L10n.Mods.sortAuthor), systemImage: "person")
            }
            Button {
                selectedSort = .version
            } label: {
                Label(vm.L(L10n.Mods.sortVersion), systemImage: "number")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11))
                Text(sortLabel)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
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
                    .font(.system(size: 11))
                Text(vm.L(L10n.Mods.configFilterLabel))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(configOnlyFilter ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configOnlyFilter ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(configOnlyFilter ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help(vm.L(L10n.Mods.configFilterLabel))
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
                        .font(.system(size: 11))
                    Text(vm.L(L10n.Mods.categoryFilter))
                        .font(.system(size: 12, weight: .medium))
                case .category(let cat):
                    Circle()
                        .fill(cat.color)
                        .frame(width: 9, height: 9)
                    Text(cat.localizedName(vm.L))
                        .font(.system(size: 12, weight: .medium))
                case .inferredTag(let tag):
                    Image(systemName: "tag.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(vm.L(L10n.ModTag.key(for: tag)))
                        .font(.system(size: 12, weight: .medium))
                case .uncategorized:
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(vm.L(L10n.Mods.categoryFilterUncategorized))
                        .font(.system(size: 12, weight: .medium))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
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
                            .fill(Color.primary.opacity(0.05))
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
                                .fill(Color.primary.opacity(0.05))
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
    @State private var isShowingDependencies = false
    /// Draft text for the Nexus mod id field inside the popover. Lazily seeded
    /// from the mod's effective id when the popover opens, so the user's in-
    /// progress edit isn't clobbered on every re-render.
    @State private var nexusIdDraft: String = ""
    @State private var nexusIdDraftSeeded: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            
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
                Text(mod.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if mod.name != mod.folderName {
                    Text(mod.folderName)
                        .font(.system(size: 11))
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
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("v\(mod.version)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
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
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("v\(vm.displayVersion(for: mod))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(mod.description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.85))
                    }
                }
                let missingDeps = vm.getMissingDependencies(for: mod)
                let disabledDeps = vm.getDisabledDependencies(for: mod)
                if !missingDeps.isEmpty || !disabledDeps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        if !missingDeps.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(String(format: vm.L(L10n.Mods.missingDependencies), missingDeps.joined(separator: ", ")))
                            }
                            .foregroundColor(.red)
                        }
                        if !disabledDeps.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.octagon.fill")
                                Text(String(format: vm.L(L10n.Mods.disabledRequiredDeps), disabledDeps.joined(separator: ", ")))
                            }
                            .foregroundColor(.red)
                        }
                    }
                    .font(.system(size: 11))
                    .padding(.top, 2)
                }
            }

            Spacer()

            // Actions (always visible)
            HStack(spacing: 12) {
                Button {
                    let baseFolder = mod.isEnabled ? "Mods" : "Mods_disabled"
                    let url = URL(fileURLWithPath: vm.gameDir)
                        .appendingPathComponent(baseFolder)
                        .appendingPathComponent(mod.folderName)
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(vm.L(L10n.Mods.openFolder))
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
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(vm.L(L10n.Settings.configCodeEditor))
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
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(vm.L(L10n.Mods.viewOnNexus))
                    .pointingHandCursor()
                }

                // Info button — always visible so the user can edit the mod's
                // category / Nexus link even when it has no dependencies or
                // pre-existing Nexus URL.
                Button {
                    isShowingDependencies = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(vm.L(L10n.Mods.viewOnNexus))
                .pointingHandCursor()
                .popover(isPresented: $isShowingDependencies, arrowEdge: .bottom) {
                    ModDetailsPopover(mod: mod, vm: vm,
                                      nexusIdDraft: $nexusIdDraft,
                                      nexusIdDraftSeeded: $nexusIdDraftSeeded)
                }
            }
            .padding(.trailing, 8)


            // macOS Native Switch Toggle
            if !isChild {
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
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .controlSize(.small)
                    .labelsHidden()
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
        .background(isHovered ? Color.secondary.opacity(0.05) : Color.clear)
        .background(
            vm.selectedModID == mod.folderName
                ? Color.accentColor.opacity(0.08)
                : Color.clear
        )
        .cornerRadius(6)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(vm.L(L10n.Mods.openInFinder)) {
                let baseFolder = mod.isEnabled ? "Mods" : "Mods_disabled"
                let url = URL(fileURLWithPath: vm.gameDir)
                    .appendingPathComponent(baseFolder)
                    .appendingPathComponent(mod.folderName)
                NSWorkspace.shared.open(url)
            }
            Button(vm.L(L10n.Settings.configCodeEditor)) {
                vm.editingModConfig = mod
            }
            // Temporary entry point into the rich detail pane (SP2 Task 4).
            // Info button keeps opening ModDetailsPopover for category/Nexus-id
            // editing — repointing it is Task 5.
            Button(vm.L(L10n.Mods.detailView)) {
                vm.viewingModDetail = mod
            }
            let effectiveLink = vm.nexusLink(for: mod)
            if !effectiveLink.isEmpty {
                Button(vm.L(L10n.Mods.viewDetailsOnNexus)) {
                    if let url = URL(string: effectiveLink) { NSWorkspace.shared.open(url) }
                }
            }
        }
    }
}

// MARK: - Mod Details Popover

/// Popover shown from a mod row's info button. Hosts three sections:
///   1. Category editor — a dropdown to pin/override the mod's category.
///   2. Nexus Mods link — shows the effective URL, lets the user open it or
///      edit the underlying Nexus mod id (which also unlocks update checks for
///      mods that don't declare a `nexus:` UpdateKey).
///   3. Dependencies — the original dependency status list.
struct ModDetailsPopover: View {
    let mod: ModItem
    @ObservedObject var vm: StarHubTHViewModel
    @Binding var nexusIdDraft: String
    @Binding var nexusIdDraftSeeded: Bool

    /// On-demand metadata fetch status (triggered after the user saves a Nexus
    /// mod id). `.idle` hides the status row; `.loading` shows a spinner.
    @State private var fetchStatus: FetchStatus = .idle

    enum FetchStatus: Equatable {
        case idle
        case loading
        case success(categoryName: String?, latestVersion: String?)
        case noApiKey
        case failed(String)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if let extra = vm.modExtra(for: mod), !extra.summary.isEmpty || !extra.pictureUrl.isEmpty {
                    previewSection(extra)
                    Divider()
                }
                categorySection
                Divider()
                nexusSection
                if !mod.dependencies.isEmpty {
                    Divider()
                    dependenciesSection
                }
            }
            .padding()
        }
        .frame(width: 320)
        .frame(maxHeight: 380)
        .onAppear { seedDraft() }
    }

    // MARK: Preview (Nexus summary + picture)

    /// Nexus-fetched preview shown at the top of the popover when available.
    /// Purely informational — never triggers a network fetch itself; it only
    /// reflects data already cached by a previous check or on-demand fetch
    /// (see `StarHubTHViewModel.modExtra(for:)`). The image view collapses to
    /// nothing while loading or on failure (no broken-image placeholder) since
    /// `AsyncImage`'s phase closure only attaches a frame in the success case.
    @ViewBuilder
    private func previewSection(_ extra: NexusUpdateChecker.NexusModExtra) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !extra.pictureUrl.isEmpty, let url = URL(string: extra.pictureUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 100)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .cornerRadius(6)
                    }
                }
            }
            if !extra.summary.isEmpty {
                Text(extra.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(4)
            }
        }
    }

    // MARK: Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.L(L10n.Mods.categoryLabel))
                .font(.headline)
            categoryPicker
            Text(vm.L(L10n.Mods.categoryEditHint))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    /// Dropdown bound to the mod's effective category. Selecting "Automatic"
    /// clears any user override (falls back to the API-fetched category);
    /// selecting a category pins it.
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

    // MARK: Nexus link

    private var nexusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.L(L10n.Mods.nexusSection))
                .font(.headline)
            let link = vm.nexusLink(for: mod)
            if !link.isEmpty {
                Button {
                    if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                } label: {
                    HStack {
                        Image(systemName: "link")
                        Text(vm.L(L10n.Mods.nexusOpenPage))
                    }
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PlainButtonStyle())
                .pointingHandCursor()
                Text(link)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(vm.L(L10n.Mods.nexusNoLink))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Divider()
            HStack(spacing: 8) {
                Text(vm.L(L10n.Mods.nexusModId))
                    .font(.system(size: 11, weight: .medium))
                TextField("191", text: $nexusIdDraft)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
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
                .font(.system(size: 10))
                .foregroundColor(.secondary)
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
        guard !nexusIdDraftSeeded else { return }
        nexusIdDraft = vm.effectiveNexusModId(for: mod)
        nexusIdDraftSeeded = true
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

    private var dependenciesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vm.L(L10n.Profiles.dependencies))
                .font(.headline)
            // No inner ScrollView here — the whole popover scrolls (see
            // `body`), and nesting a second vertical ScrollView inside that
            // one made the mouse/trackpad scroll only reach whichever one
            // the cursor happened to be over.
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
}

// MARK: - Category Badge

/// Compact colored pill shown next to a mod's author/version. The dot uses the
/// category's curated color and the text uses the localized name, so the row
/// is scannable by hue even at a glance.
struct CategoryBadge: View {
    let category: NexusCategory
    let L: (String) -> String

    var body: some View {
        HStack(spacing: 4) {
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
            .background(Color.secondary.opacity(0.15))
            .foregroundColor(.secondary)
            .clipShape(Capsule())
    }
}
