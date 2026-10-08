import SwiftUI

/// L'en-tête de l'onglet Santé d'une fiche : un verdict, puis chaque
/// vérification avec son état. Une ligne à regarder mène à sa section
/// (`onSelect`) ; une ligne non vérifiée le dit, jamais d'une coche verte.
///
/// Chaque signal est lu par l'accesseur de la section qu'il résume, avec le
/// même argument (`live` ou `mod`) — voir `ModHealthChecklist`.
struct ModHealthSummary: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @ObservedObject private var keybindScanService: KeybindScanService
    /// Le mod de la fiche (dossier logique) et sa version vivante du scan.
    let mod: ModItem
    let live: ModItem
    let onSelect: (ModHealthChecklist.Check) -> Void
    @AppStorage(UDKey.dismissedPerformanceOverlaps) private var dismissedOverlapsRaw = ""

    init(viewModel: StarHubTHViewModel, localization: LocalizationStore, mod: ModItem, live: ModItem,
         onSelect: @escaping (ModHealthChecklist.Check) -> Void) {
        self.viewModel = viewModel
        self.localization = localization
        self.keybindScanService = viewModel.keybindScanService
        self.mod = mod
        self.live = live
        self.onSelect = onSelect
    }

    private var entries: [ModHealthChecklist.Entry] {
        var inputs = ModHealthChecklist.Inputs()
        inputs.isMalicious = MaliciousModBanner.hit(for: live, in: viewModel) != nil
        inputs.anomaly = viewModel.anomaly(for: live)
        inputs.compatibilityWarning = viewModel.compatibilityWarning(for: live)?.verdict.status
        inputs.knownToCompatibilityList = live.components.contains { viewModel.modCompatibility[$0.uniqueId] != nil }
        inputs.declaredConflicts = viewModel.modConflictVerdicts
            .reportedPairs(involving: mod.folderName, installed: viewModel.scanStore.mods).count
        inputs.keybindConflicts = keybindScanService.report.map { report in
            let c = report.conflicts(affecting: mod.folderName)
            return c.collisions.count + c.gameConflicts.count
        }
        inputs.performanceOverlaps = PerformanceOverlapDetailRows
            .matches(for: live, in: viewModel.scanStore.mods.flattenedMods, dismissedRaw: dismissedOverlapsRaw).count
        inputs.nexusPage = viewModel.nexusPageState(for: live)?.state
        inputs.hasNexusPage = (Int(viewModel.resolvedNexusModId(for: mod)) ?? 0) > 0
        return ModHealthChecklist.entries(inputs)
    }

    var body: some View {
        let entries = entries
        let verdict = ModHealthChecklist.verdict(entries)
        let unmeasured = entries.filter { $0.status == .unmeasured }.count
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            HStack(alignment: .top, spacing: AppDesign.Spacing.md) {
                IconTile(icon: Self.icon(verdict.status), tint: Self.tint(verdict.status))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verdict.attention > 0
                         ? String(format: localization.L(L10n.ModHealth.titleAttention), verdict.attention)
                         : localization.L(L10n.ModHealth.titleOk))
                        .font(AppDesign.Font.headline(.semibold))
                    Text(localization.L(verdict.attention > 0 ? L10n.ModHealth.subtitleAttention
                                                              : L10n.ModHealth.subtitleOk))
                        .font(AppDesign.Font.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if unmeasured > 0 {
                        Text(String(format: localization.L(L10n.ModHealth.unmeasuredNote), unmeasured))
                            .font(AppDesign.Font.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: AppDesign.Spacing.sm)],
                      alignment: .leading, spacing: AppDesign.Spacing.xs) {
                ForEach(entries, id: \.check) { row($0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    @ViewBuilder
    private func row(_ entry: ModHealthChecklist.Entry) -> some View {
        let content = HStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: Self.icon(entry.status))
                .foregroundStyle(Self.tint(entry.status))
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(localization.L(Self.label(entry.check)))
                .font(AppDesign.Font.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AppDesign.Spacing.xs)
            Text(stateText(entry))
                .font(AppDesign.Font.caption(entry.status.needsAttention ? .semibold : .regular))
                .foregroundStyle(entry.status.needsAttention ? Self.tint(entry.status) : .secondary)
                .monospacedDigit()
                .lineLimit(1)
            if entry.status.needsAttention {
                DisclosureChevron()
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, AppDesign.Spacing.sm)
        .background(entry.status.needsAttention ? Self.tint(entry.status).opacity(AppDesign.Opacity.light) : .clear,
                    in: RoundedRectangle(cornerRadius: AppDesign.Radius.section))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)

        if entry.status.needsAttention {
            Button { onSelect(entry.check) } label: { content }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .helpIfPresent(hint(entry))
        } else {
            content.helpIfPresent(hint(entry))
        }
    }

    private func stateText(_ entry: ModHealthChecklist.Entry) -> String {
        if let count = entry.count { return "\(count)" }
        switch entry.status {
        case .ok:            return localization.L(L10n.ModHealth.stateOk)
        case .unmeasured:    return localization.L(L10n.ModHealth.stateUnmeasured)
        case .notApplicable: return localization.L(L10n.ModHealth.stateNa)
        case .info, .warning, .error:
            if entry.check == .compatibility, let status = viewModel.compatibilityWarning(for: live)?.verdict.status {
                return CompatibilityWarning.label(status, localization)
            }
            return localization.L(L10n.ModHealth.stateAttention)
        }
    }

    /// Ce que vérifie la ligne, ou pourquoi elle n'a pas pu l'être.
    private func hint(_ entry: ModHealthChecklist.Entry) -> String? {
        switch (entry.check, entry.status) {
        case (.compatibility, .unmeasured): return localization.L(L10n.ModHealth.hintCompatUnknown)
        case (.keybinds, .unmeasured):      return localization.L(L10n.ModHealth.hintKeybindsUnknown)
        case (.nexusPage, .notApplicable):  return localization.L(L10n.ModHealth.hintNexusNa)
        case (.security, _):                return localization.L(L10n.ModHealth.hintSecurity)
        case (.loading, _):                 return localization.L(L10n.ModHealth.hintLoading)
        case (.log, _):                     return localization.L(L10n.ModHealth.hintLog)
        case (.performanceOverlap, _):      return localization.L(L10n.ModHealth.hintOverlap)
        default:                            return nil
        }
    }

    static func label(_ check: ModHealthChecklist.Check) -> String {
        switch check {
        case .security:           return L10n.ModHealth.checkSecurity
        case .loading:            return L10n.ModHealth.checkLoading
        case .compatibility:      return L10n.ModHealth.checkCompatibility
        case .log:                return L10n.ModHealth.checkLog
        case .conflicts:          return L10n.ModHealth.checkConflicts
        case .keybinds:           return L10n.ModHealth.checkKeybinds
        case .performanceOverlap: return L10n.ModHealth.checkOverlap
        case .nexusPage:          return L10n.ModHealth.checkNexus
        }
    }

    /// Le relevé est la source du vocabulaire partagé (`AppDesign.Status`).
    static func status(_ status: ModHealthChecklist.Status) -> AppDesign.Status {
        switch status {
        case .error:         return .error
        case .warning:       return .warning
        case .info:          return .info
        case .ok:            return .ok
        case .unmeasured:    return .unknown
        case .notApplicable: return .notApplicable
        }
    }

    static func icon(_ status: ModHealthChecklist.Status) -> String { Self.status(status).symbol }

    static func tint(_ status: ModHealthChecklist.Status) -> Color { Self.status(status).tint }
}
