import SwiftUI

/// Collapsible SMAPI health summary for the Logs view.
///
/// Renders versions + counts in a header, and — when there are problems — lists
/// skipped mods, failed mods, and external conflicts (each `name — reason`).
/// Auto-collapses when healthy (`problemCount == 0`); the chevron toggles a
/// manual override. Shown only when the ViewModel has parsed a meaningful log
/// (gating lives in `LogsView`). Card style mirrors `SystemAlertsView`.
struct SmapiHealthCard: View {
    @ObservedObject var vm: StarHubTHViewModel

    /// nil = follow the default (collapsed when healthy). Once the user taps the
    /// chevron, this holds their explicit choice and overrides the default.
    @State private var userCollapsed: Bool? = nil

    private var diagnostics: SmapiDiagnostics { vm.smapiDiagnostics ?? SmapiDiagnostics() }

    private var isExpanded: Bool { userCollapsed ?? (diagnostics.problemCount > 0) }
    private var isHealthy: Bool { diagnostics.problemCount == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isExpanded && !isHealthy {
                problems
            }
        }
        .padding(20)
        .background(isHealthy ? Color.green.opacity(0.06) : Color.primary.opacity(0.04))
        .cornerRadius(12)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isHealthy ? .green : .orange)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if isHealthy {
                    Text(vm.L(L10n.Logs.healthHealthy))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if vm.smapiLogStale { staleBadge }

            Button { vm.revealSmapiLogInFinder() } label: {
                Image(systemName: "folder").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(vm.L(L10n.Logs.healthReveal))

            Button { userCollapsed = !isExpanded } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// Orange "Stale log" pill + a relative time. Note: `Text(date, style: .relative)`
    /// formats via the *system* locale, not the in-app L10n toggle — accepted as a
    /// minor v1 inconsistency (it is a secondary detail in the badge).
    private var staleBadge: some View {
        HStack(spacing: 4) {
            Text(vm.L(L10n.Logs.healthStale))
                .font(.system(size: 10, weight: .medium))
            if let date = vm.smapiLogDate {
                Text(date, style: .relative).font(.system(size: 10))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(4)
        .foregroundColor(.orange)
    }

    // MARK: - Problems

    private var problems: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !diagnostics.skipped.isEmpty {
                issueSection(L10n.Logs.healthSkipped, items: diagnostics.skipped)
            }
            if !diagnostics.failed.isEmpty {
                issueSection(L10n.Logs.healthFailed, items: diagnostics.failed)
            }
            if !diagnostics.externalConflicts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.L(L10n.Logs.healthConflicts))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    ForEach(diagnostics.externalConflicts, id: \.self) { conflict in
                        Text("• \(conflict)").font(.system(size: 11))
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func issueSection(_ titleKey: String, items: [SmapiDiagnostics.Issue]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vm.L(titleKey))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            ForEach(items) { issue in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(issue.name).font(.system(size: 11, weight: .medium))
                        Text(issue.reason)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Summary

    /// `SMAPI 4.5.2 · Stardew Valley 1.6.15 · 64 mods · 19 packs` (only the parts
    /// the parser actually extracted).
    private var summary: String {
        var parts: [String] = []
        if let v = diagnostics.smapiVersion { parts.append("SMAPI \(v)") }
        if let g = diagnostics.gameVersion { parts.append("Stardew Valley \(g)") }
        if let m = diagnostics.modsLoaded { parts.append("\(m) mods") }
        if let c = diagnostics.contentPacksLoaded { parts.append("\(c) packs") }
        return parts.joined(separator: " · ")
    }
}
