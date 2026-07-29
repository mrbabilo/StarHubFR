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

    /// Advisory info (risk categories, per-mod errors) exists even on a healthy
    /// log, so the expanded body has content to show when the user opens it.
    private var hasDetails: Bool {
        !diagnostics.patchedMods.isEmpty || !diagnostics.saveSerializerMods.isEmpty
            || !diagnostics.consoleMods.isEmpty || !diagnostics.topErrorMods.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isExpanded && (!isHealthy || hasDetails) {
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

    /// Body of the expanded card: what to do first, then the details behind it.
    /// Suggestions lead because they're the actionable part for a non-expert;
    /// the category lists below are the evidence.
    private var problems: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.L(L10n.Logs.healthSuggestionsTitle))
                        .font(.system(size: 11, weight: .semibold))
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { _, text in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                                .padding(.top, 1)
                            Text(text)
                                .font(.system(size: 11))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !diagnostics.skipped.isEmpty {
                issueSection(L10n.Logs.healthSkipped, items: diagnostics.skipped)
            }
            if !diagnostics.failed.isEmpty {
                issueSection(L10n.Logs.healthFailed, items: diagnostics.failed)
            }
            if !diagnostics.brokenMods.isEmpty {
                modSection(L10n.Logs.healthBroken, explanation: L10n.Logs.healthExpBroken, mods: diagnostics.brokenMods)
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
            if !diagnostics.saveSerializerMods.isEmpty {
                modSection(L10n.Logs.healthSaveSerializer, explanation: L10n.Logs.healthExpSave, mods: diagnostics.saveSerializerMods)
            }
            if !diagnostics.patchedMods.isEmpty {
                modSection(L10n.Logs.healthPatched, explanation: L10n.Logs.healthExpPatched, mods: diagnostics.patchedMods)
            }
            if !diagnostics.consoleMods.isEmpty {
                modSection(L10n.Logs.healthConsole, explanation: L10n.Logs.healthExpConsole, mods: diagnostics.consoleMods)
            }
            if !diagnostics.topErrorMods.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.L(L10n.Logs.healthTopErrors))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    ForEach(diagnostics.topErrorMods) { entry in
                        HStack(spacing: 6) {
                            Text("• \(entry.name)").font(.system(size: 11, weight: .medium))
                            Text(String(format: vm.L(L10n.Logs.healthErrorsCount), Int64(entry.count)))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    /// A named mod list preceded by a one-line, jargon-free explanation of what
    /// the category means for the player.
    private func modSection(_ titleKey: String, explanation: String, mods: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vm.L(titleKey))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Text(vm.L(explanation))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(mods, id: \.self) { mod in
                Text("• \(mod)").font(.system(size: 11))
            }
        }
    }

    // MARK: - Suggestions

    /// Actionable, plain-language advice derived from the diagnostics, ordered
    /// most-blocking first (missing dependencies and load failures before
    /// advisory notes). Formatting lives here, not in the pure parser.
    private var suggestions: [String] {
        var out: [String] = []
        let d = diagnostics

        for dep in d.missingDeps {
            out.append(String(format: vm.L(L10n.Logs.healthSgMissingDep), dep.missing, dep.mod))
        }
        // Mods already covered by a missing-dependency tip don't need a second,
        // vaguer one repeating the same root cause.
        let depMods = Set(d.missingDeps.map(\.mod))
        for issue in d.skipped where !depMods.contains(issue.name) {
            out.append(String(format: vm.L(L10n.Logs.healthSgSkipped), issue.name, issue.reason))
        }
        for issue in d.failed where !depMods.contains(issue.name) {
            out.append(String(format: vm.L(L10n.Logs.healthSgFailed), issue.name, issue.reason))
        }
        if !d.brokenMods.isEmpty {
            out.append(vm.L(L10n.Logs.healthSgBroken))
        }
        if d.externalConflicts.contains(where: { $0.contains("RivaTuner") }) {
            out.append(vm.L(L10n.Logs.healthSgRivatuner))
        }
        for mod in d.saveSerializerMods {
            out.append(String(format: vm.L(L10n.Logs.healthSgSave), mod))
        }
        if let worst = d.topErrorMods.first, worst.count >= 5 {
            out.append(String(format: vm.L(L10n.Logs.healthSgErrorMod), worst.name, Int64(worst.count)))
        }
        if d.patchedMods.count >= 15 {
            out.append(String(format: vm.L(L10n.Logs.healthSgPatchedMany), Int64(d.patchedMods.count)))
        }
        return out
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
