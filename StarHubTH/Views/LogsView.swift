import SwiftUI

struct LogsView: View {
    @ObservedObject var vm: StarHubTHViewModel

    // Source tabs: nil = All, .app = StarHubFR, .smapi = SMAPI
    @State private var selectedSource: LogSource? = nil
    // Level filter (only visible when a source is selected)
    @State private var selectedLevel: LogLevel? = nil
    @State private var searchText: String = ""
    @State private var autoScroll: Bool = true
    @State private var showClearConfirm: Bool = false

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
    }
    private var logViews: LogViews {
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
        return LogViews(filtered: filtered, counts: counts, sourceTotal: sourceTotal)
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
                levelPill(.smapi,   label: "TRACE", count: views.counts[.smapi] ?? 0)

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
                    List(views.filtered) { entry in
                        LogEntryRow(entry: entry, vm: vm)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .id(entry.id)
                    }
                    .listStyle(.plain)
                    .id(selectedSource.map { "\($0)" } ?? "all")
                    .onChange(of: vm.logEntries.count) { _, _ in
                        if autoScroll, let last = logViews.filtered.last {
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
    }

    // MARK: - Helpers

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
                    .foregroundColor(entry.source == .smapi && entry.level == .smapi
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
}
