import SwiftUI

struct LogsView: View {
    @ObservedObject var vm: StarHubTHViewModel

    // Source tabs: nil = All, .app = StarHubTH, .smapi = SMAPI
    @State private var selectedSource: LogSource? = nil
    // Level filter (only visible when a source is selected)
    @State private var selectedLevel: LogLevel? = nil
    @State private var searchText: String = ""
    @State private var autoScroll: Bool = true

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

    var body: some View {
        VStack(spacing: 0) {

            // ── Source Tab Bar ───────────────────────────────────────
            HStack(spacing: 0) {
                sourceTab(nil,       label: vm.L(L10n.Logs.filterAll),  icon: "list.bullet")
                sourceTab(.app,      label: "StarHubTH",                icon: "app.badge")
                sourceTab(.smapi,    label: "SMAPI",                     icon: "terminal")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // ── Level Filter (always visible) ────────────────────────
            HStack(spacing: 6) {
                levelPill(nil,       label: vm.L(L10n.Logs.filterAll))
                levelPill(.info,     label: "INFO")
                levelPill(.warning,  label: "WARN")
                levelPill(.error,    label: "ERROR")
                levelPill(.smapi,    label: "TRACE")
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
                        .map { "[\($0.timestamp)] [\($0.level.rawValue)] \($0.message)" }
                        .joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.clipboard").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(vm.L(L10n.Logs.copyAll))

                // Reload SMAPI log
                Button {
                    // Keep app entries, reload SMAPI entries fresh
                    vm.logEntries.removeAll { $0.source == .smapi }
                    vm.loadSmapiLog()
                } label: {
                    Image(systemName: "arrow.clockwise").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(vm.L(L10n.Logs.refreshHint))

                // Clear app logs
                Button(vm.L(L10n.Logs.clearLogs)) {
                    vm.logEntries.removeAll { $0.source == .app }
                    vm.logOutput = ""
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
                    .onChange(of: vm.logEntries.count) {
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
    private func levelPill(_ level: LogLevel?, label: String) -> some View {
        let isSelected = selectedLevel == level
        Button { selectedLevel = level } label: {
            HStack(spacing: 4) {
                if let level = level {
                    Image(systemName: level.icon).font(.system(size: 10))
                }
                Text(label).font(.system(size: 11, weight: .medium))
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
            // Source badge
            Group {
                switch entry.source {
                case .app:
                    Image(systemName: "app.badge")
                        .foregroundColor(.accentColor.opacity(0.7))
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

                // Message
                Text(entry.message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(entry.source == .app ? .primary : entry.level.color.opacity(entry.level == .smapi ? 0.75 : 1.0))
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
                NSPasteboard.general.setString(
                    "[\(entry.timestamp)] [\(entry.level.rawValue)] \(entry.message)",
                    forType: .string
                )
            }
        }
    }
}

// MARK: - Notification for mod jump
extension Notification.Name {
    static let jumpToMod = Notification.Name("StarHubTH.jumpToMod")
}
