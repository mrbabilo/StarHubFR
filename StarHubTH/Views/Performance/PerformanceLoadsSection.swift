import SwiftUI
import Charts

/// D5-B — la carte « Chargements » : dernier lancement, dernier chargement de
/// sauvegarde, leurs étapes, ce qui pèse le plus, et le verdict avant/après.
/// Ne calcule rien : tout vient de `ProbePerformanceStore` (Core, testé).
/// Chaque ligne conduit : fiche du mod, ou mise en pause réversible.
struct PerformanceLoadsSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    @State private var pendingPause: PendingPause?
    @State private var confirmProbeFirst = false
    @State private var message: String?
    @State private var showBenchmark = false

    private struct PendingPause: Identifiable {
        let mod: ModItem
        let siblings: [String]
        var id: String { mod.folderName }
    }

    private static let contentPatcherId = "Pathoschild.ContentPatcher"

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            HStack {
                header
                Spacer()
                Button(localization.L(L10n.Benchmark.open)) { showBenchmark = true }
                    .disabled(viewModel.benchmark.isActive)
            }
            PerformanceBenchmarkStatus(runner: viewModel.benchmark, localization: localization)
            if !store.probeWritesLoads {
                note(localization.L(L10n.Performance.loadsUpdateProbe))
            } else if store.loads.isEmpty {
                note(localization.L(L10n.Performance.loadsEmpty))
            } else {
                WrapHStack(spacing: AppDesign.Spacing.md) {
                    if let b = store.lastLaunch { tile(L10n.Performance.loadsLaunch, b) }
                    if let b = store.lastSave { tile(L10n.Performance.loadsSave, b) }
                }
                if let c = store.launchComparison { verdict(L10n.Performance.loadsLaunch, c) }
                if let c = store.saveComparison { verdict(L10n.Performance.loadsSave, c) }
                if let b = store.lastLaunch { breakdown(b) }
                if let b = store.lastSave { breakdown(b) }
            }
            if let message { note(message) }
        }
        .sheet(isPresented: $showBenchmark) {
            PerformanceBenchmarkSheet(viewModel: viewModel, localization: localization, isPresented: $showBenchmark)
        }
        .confirmationDialog(localization.L(L10n.Performance.loadsProbeFirstAction), isPresented: $confirmProbeFirst) {
            Button(localization.L(L10n.Performance.loadsProbeFirstAction)) {
                setProbeFirstConsent(true)
                ProbeLoadOrder.sync(gameDir: viewModel.gameDir, consent: true, probeActive: true)
            }
        } message: {
            Text(localization.L(L10n.Performance.loadsProbeFirstConfirm))
        }
        .confirmationDialog(confirmTitle,
                            isPresented: Binding(get: { pendingPause != nil },
                                                 set: { if !$0 { pendingPause = nil } }),
                            presenting: pendingPause) { pending in
            Button(localization.L(L10n.Performance.actionPause)) { perform(pending) }
        } message: { pending in
            if !pending.siblings.isEmpty {
                Text(String(format: localization.L(L10n.Performance.loadsPauseSiblings),
                            pending.siblings.joined(separator: ", ")))
            }
        }
    }

    // MARK: — Morceaux

    private var header: some View {
        HStack(spacing: AppDesign.Spacing.xs) {
            Text(localization.L(L10n.Performance.loadsTitle)).font(AppDesign.Font.headline(.semibold))
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(.rect)
                .help(localization.L(L10n.Performance.loadsHelp))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ titleKey: String, _ b: ProbeLoadBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localization.L(titleKey)).font(AppDesign.Font.footnote).foregroundColor(.secondary)
            Text(Self.duration(b.record.totalMs)).font(AppDesign.Font.rowTitle(.semibold))
            HStack(spacing: AppDesign.Spacing.xs) {
                if b.record.reload { badge(L10n.Performance.loadsReload) }
                if store.coldRecordIds.contains(b.record.id) { badge(L10n.Performance.loadsColdDisk) }
                if !b.record.complete { badge(L10n.Performance.loadsIncomplete) }
            }
        }
        .padding(AppDesign.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: AppDesign.Radius.section)
            .fill(Color.primary.opacity(AppDesign.Opacity.subtle)))
    }

    private func badge(_ key: String) -> some View {
        Text(localization.L(key)).font(AppDesign.Font.caption)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(AppDesign.Opacity.light)))
    }

    private func verdict(_ titleKey: String, _ c: ProbeLoadComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verdictText(localization.L(titleKey), c)).font(AppDesign.Font.body(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(c.modDeltas) { d in
                HStack {
                    Text(displayName(d.mod)).lineLimit(1)
                    Spacer()
                    Text((d.deltaMs < 0 ? "−" : "+") + Self.duration(abs(d.deltaMs)))
                        .monospacedDigit()
                    if !c.verdict.isDecided {
                        Text(localization.L(L10n.Performance.loadsIndicative)).foregroundColor(.secondary)
                    }
                }
                .font(AppDesign.Font.footnote)
            }
            let older = c.exclusions[.olderProbe] ?? 0
            let other = c.exclusions.filter { $0.key != .olderProbe }.values.reduce(0, +)
            if older > 0 { note(String(format: localization.L(L10n.Performance.loadsExcludedOlderProbe), older)) }
            if other > 0 { note(String(format: localization.L(L10n.Performance.loadsExcludedOther), other)) }
        }
    }

    private func breakdown(_ b: ProbeLoadBreakdown) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            Chart(Array(b.spans.enumerated()), id: \.element.id) { index, span in
                BarMark(x: .value("s", span.ms / 1000), y: .value("", ""))
                    .foregroundStyle(span.name == .waitingForPlayer
                                     ? AnyShapeStyle(Color.gray.opacity(0.35))
                                     : AnyShapeStyle(Color.accentColor.opacity(index.isMultiple(of: 2) ? 0.85 : 0.5)))
            }
            .chartYAxis(.hidden)
            .chartXAxisLabel("s", alignment: .trailing)
            .frame(height: 44)
            ForEach(b.spans) { span in
                HStack(alignment: .firstTextBaseline) {
                    Text(localization.L(L10n.Performance.span(span.name))).lineLimit(2)
                    Spacer()
                    Text(Self.duration(span.ms)).monospacedDigit()
                }
                .font(AppDesign.Font.footnote)
                if span.name != .waitingForPlayer, span.ms > 0, span.unattributedMs / span.ms > 0.05 {
                    Text("\(Self.duration(span.unattributedMs)) · \(localization.L(L10n.Performance.loadsUnattributed))")
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !b.top.isEmpty {
                Text(localization.L(L10n.Performance.loadsTop)).font(AppDesign.Font.body(.semibold))
                ForEach(b.top) { total in
                    topRow(total, launch: b.record.kind == .launch,
                           firstTickLabel: b.spans.first { $0.name == .firstTick }?.costs)
                }
                if let loop = b.entryLoopMs {
                    note(String(format: localization.L(L10n.Performance.loadsEntryNote), Self.duration(loop)))
                }
                if let loadLoop = b.loadLoopMs, let coverage = b.loadCoverage {
                    note(String(format: localization.L(L10n.Performance.loadsLoadNote),
                                Self.duration(loadLoop), coverage.seen, coverage.total))
                }
                if b.probeLoadsFirst == false {
                    note(localization.L(L10n.Performance.loadsProbeNotFirst))
                    if probeFirstConsent != true {
                        Button(localization.L(L10n.Performance.loadsProbeFirstAction)) { confirmProbeFirst = true }
                            .controlSize(.small)
                    }
                }
                if probeFirstConsent == true {
                    Button(localization.L(L10n.Performance.loadsProbeFirstUndo)) {
                        setProbeFirstConsent(false)
                        ProbeLoadOrder.sync(gameDir: viewModel.gameDir, consent: false, probeActive: true)
                    }
                    .controlSize(.small)
                }
            }
            if b.packSeamMissing {
                let version = ProbePerformanceActions.target(modId: Self.contentPatcherId, in: viewModel.mods)?.version ?? "?"
                note(String(format: localization.L(L10n.Performance.loadsPackSeamMissing), version))
            }
            if b.assetHookMissing { note(localization.L(L10n.Performance.loadsAssetHookMissing)) }
            if b.entryHookMissing { note(localization.L(L10n.Performance.loadsEntryHookMissing)) }
            if b.record.kind == .launch, b.record.health.loadHook == "missing" {
                note(localization.L(L10n.Performance.loadsLoadHookMissing))
            }
        }
    }

    private var probeFirstConsent: Bool? {
        UserDefaults.standard.object(forKey: UDKey.probeLoadEarlyConsent) as? Bool
    }

    private func setProbeFirstConsent(_ value: Bool?) {
        if let value { UserDefaults.standard.set(value, forKey: UDKey.probeLoadEarlyConsent) }
        else { UserDefaults.standard.removeObject(forKey: UDKey.probeLoadEarlyConsent) }
    }

    private func topRow(_ total: ProbeLoadModTotal, launch: Bool, firstTickLabel: [ProbeLoadCost]?) -> some View {
        let head = ProbePerformanceActions.target(modId: total.mod, in: viewModel.mods)
        let blockers = ProbePerformanceActions.pauseBlockers(modId: total.mod, in: viewModel.mods)
        // Le premier UpdateTicked de Content Patcher (chargement des packs)
        // ne passe pas par RecordSection : étiquette propre sur son span.
        let isCp = launch
            && total.mod.caseInsensitiveCompare(Self.contentPatcherId) == .orderedSame
            && (firstTickLabel?.contains { $0.mod.caseInsensitiveCompare(Self.contentPatcherId) == .orderedSame } ?? false)
        return HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.sm) {
            Button {
                if let head { viewModel.navigationStore.openModDetail(folderName: head.folderName) }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(isCp ? localization.L(L10n.Performance.loadsCpPreparing) : displayName(total.mod))
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if total.loadMs >= 1 {
                        Text(String(format: localization.L(L10n.Performance.loadsLoadPart),
                                    Self.duration(total.loadMs), Self.duration(total.entryMs)))
                            .font(AppDesign.Font.caption).foregroundColor(.secondary)
                    } else if total.entryMs >= 1 {
                        Text(String(format: localization.L(L10n.Performance.loadsEntryPart), Self.duration(total.entryMs)))
                            .font(AppDesign.Font.caption).foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.link)
            .disabled(head == nil)
            Spacer()
            Text(Self.duration(total.ms)).monospacedDigit()
            if !blockers.dependents.isEmpty {
                Image(systemName: "lock")
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18).contentShape(.rect)
                    .help(String(format: localization.L(L10n.Performance.loadsPauseBlocked),
                                 blockers.dependents.prefix(3).joined(separator: ", ")))
            } else if let head, head.isEnabled {
                Button(localization.L(L10n.Performance.actionPause)) {
                    pendingPause = PendingPause(mod: head, siblings: blockers.siblings)
                }
                .controlSize(.small)
            }
        }
        .font(AppDesign.Font.footnote)
    }

    // MARK: — Textes

    private var confirmTitle: String {
        guard let pendingPause else { return "" }
        return String(format: localization.L(L10n.Performance.confirmTitle),
                      "\(localization.L(L10n.Performance.actionPause)) — \(pendingPause.mod.name)")
    }

    private func verdictText(_ name: String, _ c: ProbeLoadComparisonResult) -> String {
        switch c.verdict {
        case .faster(let seconds, _):
            return String(format: localization.L(L10n.Performance.loadsFaster), name, Self.duration(seconds * 1000))
        case .slower(let seconds, _):
            return String(format: localization.L(L10n.Performance.loadsSlower), name, Self.duration(seconds * 1000))
        case .noDifference:
            return String(format: localization.L(L10n.Performance.loadsNoDifference), name)
        case .grayZone(let beforeCount, _):
            // Un seul point « avant » : seule une nouvelle session sous l'ancien état le complète.
            let key = beforeCount < 2 ? L10n.Performance.loadsGrayIndicative : L10n.Performance.loadsGrayRelaunch
            return String(format: localization.L(key), name)
        }
    }

    private func displayName(_ modId: String) -> String {
        ProbePerformanceActions.target(modId: modId, in: viewModel.mods).map { head in
            (head.children ?? []).first { $0.uniqueId.caseInsensitiveCompare(modId) == .orderedSame }?.name ?? head.name
        } ?? modId
    }

    /// « 1 min 50 s », « 12 s », « 0,4 s ».
    static func duration(_ ms: Double) -> String {
        let seconds = ms / 1000
        if seconds < 10 { return String(format: "%.1f s", seconds).replacingOccurrences(of: ".", with: ",") }
        let whole = Int(seconds.rounded())
        return whole < 60 ? "\(whole) s" : "\(whole / 60) min \(String(format: "%02d", whole % 60)) s"
    }

    // MARK: — Geste

    /// Jeu vérifié **au clic** : pas de pause jeu lancé.
    private func perform(_ pending: PendingPause) {
        pendingPause = nil
        guard !viewModel.isGameRunning() else {
            message = localization.L(L10n.Performance.gameRunning)
            return
        }
        if pending.mod.isEnabled { viewModel.toggleMod(pending.mod) }
        message = localization.L(L10n.Performance.loadsPauseThenRelaunch)
    }
}
