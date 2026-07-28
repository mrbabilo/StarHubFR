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

    var filteredEntries: [LogEntry] {
        vm.logEntries.filter { entry in
            let sourceMatch = selectedSource == nil || entry.source == selectedSource
            let levelMatch  = selectedLevel == nil  || entry.level  == selectedLevel
            let searchMatch = searchText.isEmpty
                || entry.message.localizedCaseInsensitiveContains(searchText)
                || (entry.modName?.localizedCaseInsensitiveContains(searchText) ?? false)
            return sourceMatch && levelMatch && searchMatch
        }
    }

    /// Entries reduced to the selected source only (no level/search filter).
    /// Drives the per-level count badges so they reflect the true severity
    /// distribution regardless of the active search text.
    private var sourceEntries: [LogEntry] {
        vm.logEntries.filter { selectedSource == nil || $0.source == selectedSource }
    }
    private func levelCount(_ level: LogLevel) -> Int {
        sourceEntries.reduce(0) { $1.level == level ? $0 + 1 : $0 }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Source Tab Bar ───────────────────────────────────────
            HStack(spacing: 0) {
                sourceTab(nil,       label: vm.L(L10n.Logs.filterAll),  icon: "list.bullet")
                sourceTab(.app,      label: "StarHubFR",                icon: "app.badge")
                sourceTab(.smapi,    label: "SMAPI",                     icon: "terminal")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // ── Level Filter (always visible) ────────────────────────
            HStack(spacing: 6) {
                levelPill(nil,      label: vm.L(L10n.Logs.filterAll), count: sourceEntries.count)
                levelPill(.info,    label: "INFO",  count: levelCount(.info))
                levelPill(.warning, label: "WARN",  count: levelCount(.warning))
                levelPill(.error,   label: "ERROR", count: levelCount(.error))
                levelPill(.smapi,   label: "TRACE", count: levelCount(.smapi))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))

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
                    let text = filteredEntries
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
            if filteredEntries.isEmpty {
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
                    List(filteredEntries) { entry in
                        LogEntryRow(entry: entry, vm: vm)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .id(entry.id)
                    }
                    .listStyle(.plain)
                    .id(selectedSource.map { "\($0)" } ?? "all")
                    .onChange(of: vm.logEntries.count) { _, _ in
                        if autoScroll, let last = filteredEntries.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            Divider()

            // ── Status bar ───────────────────────────────────────────
            HStack {
                Text(String(format: vm.L(L10n.Logs.entryCount), filteredEntries.count, vm.logEntries.count))
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
