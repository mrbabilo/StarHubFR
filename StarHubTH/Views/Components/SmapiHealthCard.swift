import SwiftUI

/// Collapsible SMAPI health summary for the Logs view.
///
/// Layout follows severity: a status line and a count-per-severity strip give
/// the verdict at a glance, then "what you can do", then the evidence grouped
/// into visually distinct blocks. Sections are cards rather than a single
/// stack — with eight of them, uniform spacing and one type size made the
/// content unreadable.
///
/// Auto-collapses when healthy (`problemCount == 0`); the chevron toggles a
/// manual override. Shown only when the ViewModel has parsed a meaningful log
/// (gating lives in `LogsView`).
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

    /// Height of the window the card sits in, measured by `LogsView`. The card
    /// can't measure it itself: inside a VStack a GeometryReader only sees the
    /// height the card was already given, which would make the sizing circular.
    var availableHeight: CGFloat = 600

    var body: some View {
        // Two thirds of the window is the target for the *whole* card, so the
        // header, its counts strip and the surrounding padding come out of that
        // budget rather than adding to it.
        card(maxBodyHeight: availableHeight * 0.66 - Self.headerAllowance)
    }

    /// Rough height of the header block plus the card's outer padding, subtracted
    /// from the budget so the card as a whole lands on its target share.
    private static let headerAllowance: CGFloat = 116

    private func card(maxBodyHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded && (!isHealthy || hasDetails) {
                Divider()
                // The body scrolls inside a bounded height: on a large modlist
                // it runs to thousands of points, which used to push the log
                // list off-screen AND carry the collapse chevron out of view,
                // making the card impossible to close. The header stays outside
                // this ScrollView so it is always reachable.
                ScrollView {
                    problems
                        .padding(AppDesignCore.Spacing.lg)
                }
                // A firm height, not a ceiling: the log list below also wants
                // all the space it can get, so with `maxHeight` SwiftUI split
                // the difference and the card only ever reached about half the
                // window. `height` makes the card claim its share first.
                .frame(height: max(200, maxBodyHeight))
            }
        }
        // A distinctly lighter/darker surface than the log list behind it: the
        // card previously used controlBackgroundColor, the very colour the Logs
        // view paints itself with, so its edges disappeared.
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: AppDesignCore.Radius.lg)
                .stroke(accent.opacity(AppDesignCore.Opacity.strong), lineWidth: 1)
        )
        .cornerRadius(AppDesignCore.Radius.lg)
        .shadow(color: Color.black.opacity(AppDesignCore.Opacity.light), radius: 6, y: 2)
    }

    /// Card tint follows the verdict, so the state reads before any text does.
    private var accent: Color { isHealthy ? .green : .orange }

    // MARK: - Header

    /// Status, version summary, and a severity strip — the whole verdict without
    /// expanding anything.
    private var header: some View {
        VStack(alignment: .leading, spacing: AppDesignCore.Spacing.sm) {
            HStack(alignment: .center, spacing: AppDesignCore.Spacing.md) {
                Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(accent)
                    .font(.system(size: 22))

                VStack(alignment: .leading, spacing: 2) {
                    Text(isHealthy ? vm.L(L10n.Logs.healthHealthy) : vm.L(L10n.Logs.healthTitle))
                        .font(.system(size: 14, weight: .semibold))
                    if !versionLine.isEmpty {
                        Text(versionLine)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if vm.smapiLogStale { staleBadge }

                Button { vm.revealSmapiLogInFinder() } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(vm.L(L10n.Logs.healthReveal))

                if !isHealthy || hasDetails {
                    Button { userCollapsed = !isExpanded } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }

            if !severityCounts.isEmpty {
                HStack(spacing: AppDesignCore.Spacing.sm) {
                    ForEach(severityCounts, id: \.label) { item in
                        countChip(item.count, item.label, item.color)
                    }
                }
            }
        }
        .padding(AppDesignCore.Spacing.lg)
        .background(accent.opacity(0.07))
    }

    /// Problem counts by kind — the overview the card used to lack entirely:
    /// previously you had to expand and count list items yourself.
    private var severityCounts: [(count: Int, label: String, color: Color)] {
        let d = diagnostics
        var out: [(Int, String, Color)] = []
        let blocking = d.skipped.count + d.failed.count + d.brokenMods.count
        if blocking > 0 { out.append((blocking, vm.L(L10n.Logs.healthCountBlocking), .red)) }
        if !d.missingDeps.isEmpty { out.append((d.missingDeps.count, vm.L(L10n.Logs.healthCountDeps), .orange)) }
        let advisory = d.saveSerializerMods.count + d.patchedMods.count + d.consoleMods.count
        if advisory > 0 { out.append((advisory, vm.L(L10n.Logs.healthCountAdvisory), .secondary)) }
        if !d.benignNotices.isEmpty { out.append((d.benignNotices.count, vm.L(L10n.Logs.healthCountBenign), .green)) }
        return out.map { (count: $0.0, label: $0.1, color: $0.2) }
    }

    private func countChip(_ count: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: AppDesignCore.Spacing.xs) {
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, AppDesignCore.Spacing.sm)
        .padding(.vertical, AppDesignCore.Spacing.xs)
        .background(color.opacity(AppDesignCore.Opacity.light))
        .cornerRadius(AppDesignCore.Radius.sm)
    }

    /// Orange "Stale log" pill + a relative time. Note: `Text(date, style: .relative)`
    /// formats via the *system* locale, not the in-app L10n toggle — accepted as a
    /// minor v1 inconsistency (it is a secondary detail in the badge).
    private var staleBadge: some View {
        HStack(spacing: AppDesignCore.Spacing.xs) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 10))
            Text(vm.L(L10n.Logs.healthStale))
                .font(.system(size: 10, weight: .medium))
            if let date = vm.smapiLogDate {
                Text(date, style: .relative).font(.system(size: 10))
            }
        }
        .padding(.horizontal, AppDesignCore.Spacing.sm)
        .padding(.vertical, 3)
        .background(Color.orange.opacity(AppDesignCore.Opacity.medium))
        .cornerRadius(AppDesignCore.Radius.sm)
        .foregroundColor(.orange)
    }

    // MARK: - Body

    /// What to do first, then the evidence behind it. Suggestions lead because
    /// they're the actionable part for a non-expert.
    private var problems: some View {
        VStack(alignment: .leading, spacing: AppDesignCore.Spacing.lg) {
            if !suggestions.isEmpty { suggestionsBlock }

            if !diagnostics.skipped.isEmpty {
                issueSection(L10n.Logs.healthSkipped, items: diagnostics.skipped, severity: .red)
            }
            if !diagnostics.failed.isEmpty {
                issueSection(L10n.Logs.healthFailed, items: diagnostics.failed, severity: .red)
            }
            if !diagnostics.brokenMods.isEmpty {
                modSection(L10n.Logs.healthBroken, explanation: L10n.Logs.healthExpBroken,
                           mods: diagnostics.brokenMods, severity: .red, logHeader: "Broken mods")
            }
            if !diagnostics.externalConflicts.isEmpty { conflictsBlock }
            if !diagnostics.saveSerializerMods.isEmpty {
                modSection(L10n.Logs.healthSaveSerializer, explanation: L10n.Logs.healthExpSave,
                           mods: diagnostics.saveSerializerMods, severity: .orange,
                           logHeader: "Changed save serializer")
            }
            if !diagnostics.patchedMods.isEmpty {
                modSection(L10n.Logs.healthPatched, explanation: L10n.Logs.healthExpPatched,
                           mods: diagnostics.patchedMods, severity: .secondary,
                           logHeader: "Patched game code")
            }
            if !diagnostics.consoleMods.isEmpty {
                modSection(L10n.Logs.healthConsole, explanation: L10n.Logs.healthExpConsole,
                           mods: diagnostics.consoleMods, severity: .secondary,
                           logHeader: "Direct console access")
            }
            if !diagnostics.topErrorMods.isEmpty { topErrorsBlock }
            if !diagnostics.benignNotices.isEmpty { benignBlock }
        }
    }

    // MARK: - Blocks

    private var suggestionsBlock: some View {
        sectionCard(.accentColor) {
            sectionTitle(vm.L(L10n.Logs.healthSuggestionsTitle), icon: "lightbulb.fill", color: .accentColor)
            VStack(alignment: .leading, spacing: AppDesignCore.Spacing.sm) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .top, spacing: AppDesignCore.Spacing.sm) {
                        Text("\(index + 1).")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.accentColor)
                            .frame(width: 16, alignment: .trailing)
                        Text(text)
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var conflictsBlock: some View {
        sectionCard(.orange) {
            sectionTitle(vm.L(L10n.Logs.healthConflicts), icon: "bolt.trianglebadge.exclamationmark.fill", color: .orange)
            ForEach(diagnostics.externalConflicts, id: \.self) { conflict in
                Text(conflict).font(.system(size: 12))
            }
        }
    }

    private var topErrorsBlock: some View {
        sectionCard(.secondary) {
            sectionTitle(vm.L(L10n.Logs.healthTopErrors), icon: "chart.bar.fill", color: .secondary)
            VStack(spacing: AppDesignCore.Spacing.xs) {
                ForEach(diagnostics.topErrorMods) { entry in
                    HStack(spacing: AppDesignCore.Spacing.sm) {
                        Text(entry.name).font(.system(size: 12, weight: .medium))
                        Text(String(format: vm.L(L10n.Logs.healthErrorsCount), Int64(entry.count)))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, AppDesignCore.Spacing.xs)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(AppDesignCore.Opacity.light))
                            .cornerRadius(3)
                        Spacer()
                        modActions(entry.name)
                    }
                }
            }
        }
    }

    private var benignBlock: some View {
        sectionCard(.green) {
            sectionTitle(vm.L(L10n.Logs.healthBenign), icon: "checkmark.circle.fill", color: .green)
            Text(vm.L(L10n.Logs.healthExpBenign))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: AppDesignCore.Spacing.md) {
                ForEach(diagnostics.benignNotices) { notice in
                    VStack(alignment: .leading, spacing: AppDesignCore.Spacing.xs) {
                        // Name the mod up front: the player needs to know *which*
                        // mod is fine, not just that something is.
                        if let mod = notice.mod {
                            HStack(spacing: AppDesignCore.Spacing.xs) {
                                Text(mod).font(.system(size: 12, weight: .medium))
                                if notice.count > 1 {
                                    Text("×\(notice.count)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(AppDesignCore.Opacity.light))
                                        .cornerRadius(3)
                                }
                                Spacer()
                                modActions(mod)
                            }
                        }
                        Text(benignText(notice))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        // The original line, so the explanation can be checked
                        // against the raw log.
                        if !notice.sample.isEmpty {
                            Text(notice.sample)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary.opacity(AppDesignCore.Opacity.secondary))
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(AppDesignCore.Spacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(AppDesignCore.Radius.sm)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section building blocks

    /// A section heading: a filled icon chip plus the title, sitting on the
    /// section's own tinted strip so each block announces itself.
    private func sectionTitle(_ text: String, icon: String, color: Color,
                              trailing: (() -> AnyView)? = nil) -> some View {
        HStack(spacing: AppDesignCore.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(color)
                .cornerRadius(AppDesignCore.Radius.sm)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.3)
            if let trailing { trailing() }
            Spacer()
        }
    }

    /// Wraps a section in its own surface with a severity rail, so blocks read
    /// as separate cards instead of one long stack of paragraphs.
    private func sectionCard<Content: View>(_ color: Color,
                                            @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: AppDesignCore.Spacing.sm) {
                content()
            }
            .padding(AppDesignCore.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(color.opacity(0.06))
        .cornerRadius(AppDesignCore.Radius.md)
    }

    /// A named mod list preceded by a one-line, jargon-free explanation of what
    /// the category means for the player.
    private func modSection(_ titleKey: String, explanation: String, mods: [String],
                            severity: Color, logHeader: String? = nil) -> some View {
        sectionCard(severity) {
            sectionTitle(vm.L(titleKey), icon: "shippingbox.fill", color: severity) {
                AnyView(
                    Group {
                        // Shows SMAPI's own block for this category — the full
                        // list of affected mods, beyond the few shown here.
                        if let logHeader {
                            Button {
                                NotificationCenter.default.post(name: .showLogSection, object: logHeader)
                            } label: {
                                Image(systemName: "list.bullet.rectangle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            .help(vm.L(L10n.Logs.healthShowSection))
                        }
                    }
                )
            }
            Text(vm.L(explanation))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Cap long lists: with ~900 mods a category can hold dozens of
            // entries. The full picture stays in the raw SMAPI log.
            VStack(spacing: AppDesignCore.Spacing.xs) {
                ForEach(mods.prefix(Self.maxListedMods), id: \.self) { mod in
                    HStack(spacing: AppDesignCore.Spacing.sm) {
                        Text(mod).font(.system(size: 12))
                        Spacer()
                        modActions(mod)
                    }
                }
            }
            if mods.count > Self.maxListedMods {
                Text(String(format: vm.L(L10n.Logs.healthAndMore), Int64(mods.count - Self.maxListedMods)))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func issueSection(_ titleKey: String, items: [SmapiDiagnostics.Issue],
                              severity: Color) -> some View {
        sectionCard(severity) {
            sectionTitle(vm.L(titleKey), icon: "xmark.octagon.fill", color: severity)
            VStack(alignment: .leading, spacing: AppDesignCore.Spacing.sm) {
                ForEach(items) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: AppDesignCore.Spacing.sm) {
                            Text(issue.name).font(.system(size: 12, weight: .medium))
                            Spacer()
                            modActions(issue.name)
                        }
                        Text(issue.reason)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Max mods listed per category before collapsing into "…and N more".
    private static let maxListedMods = 8

    /// The two per-mod actions, grouped so they read as one control rather than
    /// two loose glyphs floating next to the name.
    private func modActions(_ mod: String) -> some View {
        HStack(spacing: 2) {
            actionButton("arrow.right.circle", help: L10n.Logs.healthOpenMod) {
                NotificationCenter.default.post(name: .jumpToMod, object: mod)
            }
            actionButton("text.magnifyingglass", help: L10n.Logs.healthShowInLog) {
                NotificationCenter.default.post(name: .filterLogsToMod, object: mod)
            }
        }
    }

    private func actionButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(vm.L(help))
    }

    /// Plain-language reassurance for a known-harmless error. The mod name is
    /// rendered separately above, so the wording stays generic and isn't
    /// repeated in the sentence.
    private func benignText(_ notice: SmapiDiagnostics.BenignNotice) -> String {
        switch notice.kind {
        case .galaxyAuth:        return vm.L(L10n.Logs.healthBenignGalaxy)
        case .apiIntegration:    return vm.L(L10n.Logs.healthBenignApiGeneric)
        case .optionalModMissing: return vm.L(L10n.Logs.healthBenignOptionalGeneric)
        case .modContentParse:   return vm.L(L10n.Logs.healthBenignParseGeneric)
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
            out.append(advice(for: issue, fallback: L10n.Logs.healthSgSkipped))
        }
        for issue in d.failed where !depMods.contains(issue.name) {
            out.append(advice(for: issue, fallback: L10n.Logs.healthSgFailed))
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
        // Keep the advice list readable: per-mod tips could otherwise run to
        // dozens of lines. Ordering above puts the most blocking ones first,
        // and the categories below still list every affected mod.
        if out.count > Self.maxSuggestions {
            let hidden = out.count - Self.maxSuggestions
            out = Array(out.prefix(Self.maxSuggestions))
            out.append(String(format: vm.L(L10n.Logs.healthAndMore), Int64(hidden)))
        }
        return out
    }

    /// Max suggestions shown before collapsing into "…and N more".
    private static let maxSuggestions = 6

    /// Maps a load failure to the most specific fix we can offer. SMAPI's raw
    /// reasons are accurate but cryptic ("its DLL couldn't be loaded: … already
    /// loaded"), so recognized families get a concrete instruction; anything
    /// unrecognized falls back to quoting the reason verbatim.
    private static let adviceRules: [(patterns: [String], key: String)] = [
        (["already loaded", "two copies", "duplicate"], L10n.Logs.healthSgDuplicate),
        (["requires a newer version", "older version of smapi", "needs smapi",
          "compatible with stardew valley", "requires stardew valley",
          "not compatible with this version"], L10n.Logs.healthSgGameVersion),
        (["manifest.json", "manifest is invalid", "invalid manifest",
          "no manifest", "couldn't parse manifest"], L10n.Logs.healthSgManifest),
        (["not in a folder", "wrong folder", "subfolder"], L10n.Logs.healthSgFolder)
    ]

    private func advice(for issue: SmapiDiagnostics.Issue, fallback: String) -> String {
        let reason = issue.reason.lowercased()
        for rule in Self.adviceRules where rule.patterns.contains(where: reason.contains) {
            return String(format: vm.L(rule.key), issue.name)
        }
        return String(format: vm.L(fallback), issue.name, issue.reason)
    }

    // MARK: - Summary

    /// `SMAPI 4.5.2 · Stardew Valley 1.6.15 · 64 mods · 19 packs` (only the parts
    /// the parser actually extracted).
    private var versionLine: String {
        var parts: [String] = []
        if let v = diagnostics.smapiVersion { parts.append("SMAPI \(v)") }
        if let g = diagnostics.gameVersion { parts.append("Stardew Valley \(g)") }
        if let m = diagnostics.modsLoaded { parts.append(String(format: vm.L(L10n.Logs.healthModsCount), Int64(m))) }
        if let c = diagnostics.contentPacksLoaded { parts.append(String(format: vm.L(L10n.Logs.healthPacksCount), Int64(c))) }
        return parts.joined(separator: "  ·  ")
    }
}
