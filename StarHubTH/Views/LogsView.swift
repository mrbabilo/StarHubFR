import SwiftUI

struct LogsView: View {
    @ObservedObject var vm: StarHubTHViewModel

    // Source tabs: nil = All, .app = StarHubFR, .smapi = SMAPI
    @State private var selectedSource: LogSource? = nil
    // Level filter (TRACE pill hidden on the StarHubFR source)
    @State private var selectedLevel: LogLevel? = nil
    @State private var searchText: String = ""
    @State private var autoScroll: Bool = true
    @State private var showClearConfirm: Bool = false
    /// Ids of folded families the user expanded.
    @State private var expandedGroups: Set<String> = []
    /// Group the list into per-mod sections instead of one chronological stream.
    @State private var groupByMod: Bool = false
    /// When set, the list shows only this SMAPI warning-group block (header +
    /// the mods it lists), as written in the log.
    @State private var sectionHeader: String? = nil
    /// Ids of the per-mod sections currently expanded.
    @State private var expandedMods: Set<String> = []

    /// Single-pass derivation of everything the Logs UI needs from the raw
    /// entries: the filtered list (source + level + search) for the `List`,
    /// copy-all and status bar, plus per-level counts scoped to the selected
    /// source (so the level pills reflect the true severity distribution
    /// regardless of the active search) and the source-scoped total.
    ///
    /// Replaces three separate computed properties that each did a full O(n)
    /// pass — and were re-evaluated on every access (the List, isEmpty, copy,
    /// status bar, and each of the 5 level pills), so a single body render ran
    /// ~9 full passes over up to 2000 entries. Now one pass, accessed once.
    private struct LogViews {
        let filtered: [LogEntry]
        let counts: [LogLevel: Int]
        let sourceTotal: Int
        /// `filtered` folded into rows: repetitive families become one row.
        let rows: [LogRow]
        /// `filtered` partitioned per mod (problem mods first, framework last).
        let modGroups: [LogNoise.ModGroup]
    }

    /// One line of the log list: either a single entry, or a run of consecutive
    /// same-family entries folded into a single expandable row.
    private enum LogRow: Identifiable {
        case single(LogEntry)
        case group(id: String, entries: [LogEntry])

        var id: String {
            switch self {
            case .single(let e):    return e.id.uuidString
            case .group(let id, _): return id
            }
        }
    }
    private var logViews: LogViews {
        // Showing one warning-group block: SMAPI writes it as consecutive lines,
        // so it's located by span in the SMAPI entries rather than by matching
        // each line — the separator and blurb have nothing in common to match.
        if let header = sectionHeader {
            let smapi = vm.logEntries.filter { $0.source == .smapi }
            let block = LogNoise.warningGroupRange(
                messages: smapi.map { $0.message }, header: header
            ).map { Array(smapi[$0]) } ?? []
            return LogViews(filtered: block, counts: [:], sourceTotal: block.count,
                            rows: block.map { LogRow.single($0) }, modGroups: [])
        }

        var filtered: [LogEntry] = []
        var counts: [LogLevel: Int] = [:]
        var sourceTotal = 0
        let source = selectedSource
        let level = selectedLevel
        let search = searchText
        for entry in vm.logEntries {
            guard source == nil || entry.source == source else { continue }
            sourceTotal += 1
            counts[entry.level, default: 0] += 1
            if (level == nil || entry.level == level),
               search.isEmpty
                || entry.message.localizedCaseInsensitiveContains(search)
                || (entry.modName?.localizedCaseInsensitiveContains(search) ?? false) {
                filtered.append(entry)
            }
        }
        // Only pay for the grouping when that view is actually on screen.
        let groups = groupByMod
            ? LogNoise.groupByMod(
                count: filtered.count,
                mod: { filtered[$0].modName },
                isError: { filtered[$0].level == .error },
                isWarning: { filtered[$0].level == .warning })
            : []
        return LogViews(filtered: filtered, counts: counts, sourceTotal: sourceTotal,
                        rows: groupByMod ? [] : Self.fold(filtered),
                        modGroups: groups)
    }

    /// Folds runs of consecutive same-family entries into single rows. Only
    /// *consecutive* runs are folded, so the log keeps its chronological
    /// reading: a burst of 646 "loaded asset 'X'" lines collapses, but two
    /// bursts separated by other activity stay apart.
    ///
    /// Groups are keyed on the first entry's id, so the key is stable across
    /// renders (needed for the expanded/collapsed state to stick).
    private static func fold(_ entries: [LogEntry]) -> [LogRow] {
        var rows: [LogRow] = []
        var run: [LogEntry] = []
        var runSignature: String?

        func flush() {
            guard !run.isEmpty else { return }
            if run.count >= LogNoise.groupingThreshold, let first = run.first {
                rows.append(.group(id: first.id.uuidString, entries: run))
            } else {
                rows.append(contentsOf: run.map { LogRow.single($0) })
            }
            run = []
            runSignature = nil
        }

        for entry in entries {
            let signature = LogNoise.signature(of: entry.message)
            // A family is per (signature, level, mod): same wording from two
            // different mods stays distinguishable.
            let key = "\(signature)|\(entry.level.rawValue)|\(entry.modName ?? "")"
            if key == runSignature {
                run.append(entry)
            } else {
                flush()
                runSignature = key
                run = [entry]
            }
        }
        flush()
        return rows
    }

    var body: some View {
        let views = logViews
        return VStack(spacing: 0) {

            // ── Source + Level filter (one row) ─────────────────────
            HStack(spacing: 10) {
                sourceTab(nil,    label: vm.L(L10n.Logs.filterAll), icon: "list.bullet")
                sourceTab(.app,   label: "StarHubFR",               icon: "app.badge")
                sourceTab(.smapi, label: "SMAPI",                    icon: "terminal")

                Divider().frame(height: 16)

                levelPill(nil,      label: vm.L(L10n.Logs.filterAll), count: views.sourceTotal)
                levelPill(.info,    label: "INFO",  count: views.counts[.info] ?? 0)
                levelPill(.warning, label: "WARN",  count: views.counts[.warning] ?? 0)
                levelPill(.error,   label: "ERROR", count: views.counts[.error] ?? 0)
                if selectedSource != .app {
                    levelPill(.trace, label: "TRACE", count: views.counts[.trace] ?? 0)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // ── Toolbar ──────────────────────────────────────────────
            HStack(spacing: 10) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField(vm.L(L10n.Logs.searchPlaceholder), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                         .help(vm.L(L10n.Logs.clearSearchHint))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)

                Spacer()

                // Auto-scroll
                Button { autoScroll.toggle() } label: {
                    Image(systemName: autoScroll ? "arrow.down.to.line" : "arrow.down.to.line.compact")
                        .foregroundColor(autoScroll ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(vm.L(L10n.Logs.autoScrollHint))

                // Copy
                Button {
                    let text = views.filtered
                        .map { $0.formattedLine }
                        .joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.clipboard").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(vm.L(L10n.Logs.copyAll))

                // Group by mod
                Button { groupByMod.toggle() } label: {
                    Image(systemName: groupByMod ? "rectangle.grid.1x2.fill" : "rectangle.grid.1x2")
                        .foregroundColor(groupByMod ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(vm.L(L10n.Logs.groupByMod))

                // Reload SMAPI log (loadSmapiLog replaces existing SMAPI entries)
                Button {
                    vm.loadSmapiLog()
                } label: {
                    Image(systemName: "arrow.clockwise").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(vm.L(L10n.Logs.refreshHint))

                // Clear app logs (destructive — confirmed via dialog below)
                Button(vm.L(L10n.Logs.clearLogs)) {
                    showClearConfirm = true
                }
                .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Section view is a dead end without a visible way out, since the
            // usual filters don't apply while it's active.
            if let header = sectionHeader {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 11))
                    Text(header)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Button(vm.L(L10n.Logs.backToAllLogs)) { sectionHeader = nil }
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.08))
                Divider()
            }

            // ── Entries ──────────────────────────────────────────────
            // SMAPI health card - shown on All + SMAPI tabs only
            if selectedSource != .app, let diag = vm.smapiDiagnostics, !diag.isEmpty {
                SmapiHealthCard(vm: vm)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
            }

            if views.filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.checkmark")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(vm.L(L10n.Logs.noLogs))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    // LazyVStack (not List): List was constructing/measuring all
                    // ~2000 rows when switching to the "All" tab (8-10 s beach
                    // ball) instead of virtualizing. LazyVStack only builds rows
                    // as they scroll into view, so growing the set to thousands
                    // is instant. `.id` per row keeps `proxy.scrollTo` working.
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if groupByMod {
                                ForEach(views.modGroups) { group in
                                    modSection(group, allEntries: views.filtered)
                                }
                            } else {
                                rowList(views.rows)
                            }
                        }
                    }
                    .onChange(of: vm.logEntries.count) { _, _ in
                        // Pointless when grouped: the list is no longer
                        // chronological, so the newest line isn't at the bottom.
                        if autoScroll, !groupByMod, let last = logViews.filtered.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            Divider()

            // ── Status bar ───────────────────────────────────────────
            HStack {
                Text(String(format: vm.L(L10n.Logs.entryCount), views.filtered.count, vm.logEntries.count))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .confirmationDialog(vm.L(L10n.Logs.clearConfirmTitle),
                            isPresented: $showClearConfirm,
                            titleVisibility: .visible) {
            // macOS auto-appends a localized Cancel button since none here has
            // role .cancel. Only app entries are wiped; SMAPI entries are kept.
            Button(vm.L(L10n.Logs.clearLogs), role: .destructive) {
                vm.logEntries.removeAll { $0.source == .app }
            }
        } message: {
            Text(vm.L(L10n.Logs.clearConfirmMessage))
        }
        .onAppear {
            if vm.logEntries.filter({ $0.source == .smapi }).isEmpty {
                vm.loadSmapiLog()
            }
        }
        .onDisappear {
            vm.stopSmapiLogWatcher()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filterLogsToMod)) { note in
            guard let mod = note.object as? String else { return }
            // Show every level from every source so the mod's lines can't be
            // filtered out by whatever the user had selected.
            sectionHeader = nil
            selectedSource = nil
            selectedLevel = nil
            searchText = mod
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLogSection)) { note in
            guard let header = note.object as? String else { return }
            searchText = ""
            selectedLevel = nil
            groupByMod = false
            sectionHeader = header
        }
    }

    // MARK: - Helpers

    /// The chronological stream: single entries plus folded families.
    @ViewBuilder
    private func rowList(_ rows: [LogRow]) -> some View {
        ForEach(rows) { row in
            switch row {
            case .single(let entry):
                LogEntryRow(entry: entry, vm: vm)
                    .id(entry.id)
            case .group(let id, let entries):
                LogGroupRow(
                    entries: entries,
                    isExpanded: expandedGroups.contains(id),
                    vm: vm,
                    toggle: { toggle(id, in: &expandedGroups) }
                )
                .id(id)
            }
        }
    }

    /// One collapsible per-mod section. Its lines keep the family folding of the
    /// chronological view, so a chatty mod stays readable once expanded.
    @ViewBuilder
    private func modSection(_ group: LogNoise.ModGroup, allEntries: [LogEntry]) -> some View {
        let isExpanded = expandedMods.contains(group.id)
        VStack(alignment: .leading, spacing: 0) {
            Button { toggle(group.id, in: &expandedMods) } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: 14)

                    Text(group.mod ?? vm.L(L10n.Logs.frameworkGroup))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(group.mod == nil ? .secondary : .primary)

                    Text("\(group.lineCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)

                    // Severity dot: lets a problem mod be spotted while collapsed.
                    if group.errorCount > 0 {
                        Circle().fill(Color.red).frame(width: 6, height: 6)
                    } else if group.warningCount > 0 {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                    }

                    Spacer()
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            if isExpanded {
                rowList(Self.fold(group.indices.map { allEntries[$0] }))
                    .padding(.leading, 12)
            }
        }
        .padding(.vertical, 1)
    }

    private func toggle(_ id: String, in set: inout Set<String>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    @ViewBuilder
    private func sourceTab(_ source: LogSource?, label: String, icon: String) -> some View {
        let isSelected = selectedSource == source
        Button {
            selectedSource = source
            selectedLevel = nil  // reset level filter on source change
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundColor(isSelected ? .white : .secondary)
            .cornerRadius(7)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func levelPill(_ level: LogLevel?, label: String, count: Int) -> some View {
        let isSelected = selectedLevel == level
        let badgeColor = level?.color ?? Color.secondary
        Button { selectedLevel = level } label: {
            HStack(spacing: 4) {
                if let level = level {
                    Image(systemName: level.icon).font(.system(size: 10))
                }
                Text(label).font(.system(size: 11, weight: .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isSelected ? badgeColor : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(badgeColor.opacity(isSelected ? 0.22 : 0.12))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isSelected ? (level?.color ?? Color.accentColor).opacity(0.15) : Color.clear)
            .foregroundColor(isSelected ? (level?.color ?? Color.accentColor) : .secondary)
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? (level?.color ?? Color.accentColor).opacity(0.35) : Color.clear,
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Folded family row

/// A run of repetitive same-family entries shown as one line ("Content Patcher
/// loaded asset … — 646 similar lines"), expandable to the individual entries.
/// Nothing is discarded: the detail is one click away.
struct LogGroupRow: View {
    let entries: [LogEntry]
    let isExpanded: Bool
    @ObservedObject var vm: StarHubTHViewModel
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: 14)
                        .padding(.top, 2)

                    Text(entries.first?.timestamp ?? "—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 58, alignment: .leading)

                    VStack(alignment: .leading, spacing: 1) {
                        if let mod = entries.first?.modName {
                            Text(mod)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.accentColor)
                        }
                        Text(entries.first?.message ?? "")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor((entries.first?.level.color ?? .primary).opacity(0.75))
                            .lineLimit(1)
                        Text(String(format: vm.L(L10n.Logs.similarLines), Int64(entries.count)))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.03))
                )
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(vm.L(L10n.Logs.similarLinesHint))

            if isExpanded {
                ForEach(entries) { entry in
                    LogEntryRow(entry: entry, vm: vm)
                        .padding(.leading, 16)
                }
            }
        }
    }
}

// MARK: - Log Entry Row
struct LogEntryRow: View {
    let entry: LogEntry
    @ObservedObject var vm: StarHubTHViewModel
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Source badge. For app entries the app-badge shape stays as a
            // source cue, but it is tinted by severity (level.color) so an
            // app error/warning is no longer indistinguishable from info.
            // SMAPI entries show the level icon, also severity-colored.
            Group {
                switch entry.source {
                case .app:
                    Image(systemName: "app.badge")
                        .foregroundColor(entry.level.color)
                case .smapi:
                    Image(systemName: entry.level.icon)
                        .foregroundColor(entry.level.color)
                }
            }
            .font(.system(size: 11))
            .frame(width: 14)
            .padding(.top, 1)

            // Timestamp
            Text(entry.timestamp)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                // Clickable mod name badge
                if let modName = entry.modName {
                    Button {
                        NotificationCenter.default.post(name: .jumpToMod, object: modName)
                    } label: {
                        Text(modName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }

                // Message — colored by severity for BOTH sources (previously
                // app entries were always primary, hiding errors/warnings).
                // SMAPI TRACE entries are dimmed since they're verbose/noisy.
                Text(entry.message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(entry.source == .smapi && entry.level == .trace
                        ? entry.level.color.opacity(0.75)
                        : entry.level.color)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(vm.L(L10n.Logs.copyLine)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.formattedLine, forType: .string)
            }
        }
    }
}

// MARK: - Notification for mod jump
extension Notification.Name {
    static let jumpToMod = Notification.Name("StarHubTH.jumpToMod")
    /// Posted with a mod name to scope the Logs view to that mod's entries —
    /// lets the health card send the player straight to the underlying lines.
    static let filterLogsToMod = Notification.Name("StarHubTH.filterLogsToMod")
    /// Posted with a SMAPI warning-group header ("Changed save serializer", …)
    /// to show that block of the log verbatim, listing every affected mod.
    static let showLogSection = Notification.Name("StarHubTH.showLogSection")
}
