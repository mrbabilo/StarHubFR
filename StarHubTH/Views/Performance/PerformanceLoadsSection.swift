import SwiftUI

/// D5-B — la carte « Chargements », en tête de l'onglet : comparaison
/// automatique, indépendante des sélecteurs Avant/Après de la partie « en
/// jeu ». D'abord le verdict (une tuile par type), puis le détail du type
/// choisi (étapes, mods qui pèsent), enfin la qualité de la mesure, repliée.
/// Ne calcule rien : tout vient de `ProbePerformanceStore` (Core, testé).
/// Chaque ligne conduit : fiche du mod, ou mise en pause réversible.
struct PerformanceLoadsSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    @State private var pendingPause: PendingPause?
    /// Le consentement « sonde en tête » (`nil` = jamais demandé), réglé dans
    /// la carte « Sonde » : `@AppStorage` re-rend celle-ci quand il change.
    @AppStorage(UDKey.probeLoadEarlyConsent) private var consentShown: Bool?
    @State private var message: String?
    @State private var showBenchmark = false
    @State private var qualityExpanded = false
    @AppStorage(UDKey.performanceLoadsDetail) private var detailKind = ProbeLoadRecord.Kind.launch.rawValue

    private struct PendingPause: Identifiable {
        let mod: ModItem
        let siblings: [String]
        var id: String { mod.folderName }
    }

    static let contentPatcherId = "Pathoschild.ContentPatcher"

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            HStack {
                header
                Spacer()
                Button(localization.L(L10n.Benchmark.open)) { showBenchmark = true }
                    .clickableCursor()
                    .disabled(viewModel.benchmark.isActive)
            }
            note(localization.L(L10n.Performance.loadsSubtitle))
            PerformanceBenchmarkStatus(runner: viewModel.benchmark, localization: localization)
            if !store.probeWritesLoads {
                note(localization.L(L10n.Performance.loadsUpdateProbe))
            } else if store.loads.isEmpty {
                note(localization.L(L10n.Performance.loadsEmpty))
            } else {
                WrapHStack(spacing: AppDesign.Spacing.md) {
                    if let b = store.lastLaunch { tile(L10n.Performance.loadsLaunch, b, store.launchComparison) }
                    if let b = store.lastSave { tile(L10n.Performance.loadsSave, b, store.saveComparison) }
                }
                detail
                quality
            }
            if let message { note(message) }
        }
        .sheet(isPresented: $showBenchmark) {
            PerformanceBenchmarkSheet(viewModel: viewModel, localization: localization, isPresented: $showBenchmark)
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

    private func tile(_ titleKey: String, _ b: ProbeLoadBreakdown, _ c: ProbeLoadComparisonResult?) -> some View {
        PerformanceLoadsVerdict(localization: localization, titleKey: titleKey, breakdown: b, comparison: c,
                                isCold: store.coldRecordIds.contains(b.record.id), displayName: displayName)
    }

    /// Le détail du type choisi ; sans sélecteur quand un seul existe, sinon
    /// un choix mémorisé « Sauvegarde » afficherait une carte vide.
    @ViewBuilder
    private var detail: some View {
        let both = store.lastLaunch != nil && store.lastSave != nil
        let shown = detailKind == ProbeLoadRecord.Kind.save.rawValue
            ? (store.lastSave ?? store.lastLaunch) : (store.lastLaunch ?? store.lastSave)
        if let shown {
            Divider()
            if both {
                Picker("", selection: $detailKind) {
                    Text(localization.L(L10n.Performance.loadsDetailLaunch)).tag(ProbeLoadRecord.Kind.launch.rawValue)
                    Text(localization.L(L10n.Performance.loadsDetailSave)).tag(ProbeLoadRecord.Kind.save.rawValue)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            PerformanceLoadsTimeline(localization: localization, breakdown: shown)
            if !shown.top.isEmpty {
                PerformanceLoadsTopMods(viewModel: viewModel, localization: localization, breakdown: shown,
                                        displayName: displayName) { mod, siblings in
                    pendingPause = PendingPause(mod: mod, siblings: siblings)
                }
            }
        }
    }

    /// Ce qui borne la confiance : mesures écartées, accroches absentes,
    /// couverture. Replié, son compte en titre.
    @ViewBuilder
    private var quality: some View {
        let notes = qualityNotes
        if !notes.isEmpty {
            DisclosureGroup(isExpanded: $qualityExpanded) {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                    ForEach(notes, id: \.self) { note($0) }
                }
                .padding(.top, AppDesign.Spacing.xs)
            } label: {
                Text(String(format: localization.L(L10n.Performance.loadsQuality), notes.count))
                    .font(AppDesign.Font.footnote(.semibold))
            }
        }
    }

    private var qualityNotes: [String] {
        var notes: [String] = []
        for (key, c) in [(L10n.Performance.loadsLaunch, store.launchComparison),
                         (L10n.Performance.loadsSave, store.saveComparison)] {
            guard let c else { continue }
            let name = localization.L(key)
            let older = c.exclusions[.olderProbe] ?? 0
            let other = c.exclusions.filter { $0.key != .olderProbe }.values.reduce(0, +)
            if older > 0 {
                notes.append("\(name) — " + String(format: localization.L(L10n.Performance.loadsExcludedOlderProbe), older))
            }
            if other > 0 {
                notes.append("\(name) — " + String(format: localization.L(L10n.Performance.loadsExcludedOther), other))
            }
        }
        for b in [store.lastLaunch, store.lastSave].compactMap({ $0 }) {
            if let loop = b.entryLoopMs {
                notes.append(String(format: localization.L(L10n.Performance.loadsEntryNote), Self.duration(loop)))
            }
            if let loadLoop = b.loadLoopMs, let coverage = b.loadCoverage {
                notes.append(String(format: localization.L(L10n.Performance.loadsLoadNote),
                                    Self.duration(loadLoop), coverage.seen, coverage.total))
            }
            // Refusé : l'offre ne revient pas, le constat reste ici.
            if b.probeLoadsFirst == false, consentShown == false {
                notes.append(localization.L(L10n.Performance.loadsProbeNotFirst))
            }
            if b.packSeamMissing {
                let version = ProbePerformanceActions.target(modId: Self.contentPatcherId, in: viewModel.mods)?.version ?? "?"
                notes.append(String(format: localization.L(L10n.Performance.loadsPackSeamMissing), version))
            }
            if b.assetHookMissing { notes.append(localization.L(L10n.Performance.loadsAssetHookMissing)) }
            if b.entryHookMissing { notes.append(localization.L(L10n.Performance.loadsEntryHookMissing)) }
            if b.record.kind == .launch, b.record.health.loadHook == "missing" {
                notes.append(localization.L(L10n.Performance.loadsLoadHookMissing))
            }
        }
        // Une même accroche absente des deux côtés ne se dit qu'une fois.
        var seen = Set<String>()
        return notes.filter { seen.insert($0).inserted }
    }

    // MARK: — Textes

    private var confirmTitle: String {
        guard let pendingPause else { return "" }
        return String(format: localization.L(L10n.Performance.confirmTitle),
                      "\(localization.L(L10n.Performance.actionPause)) — \(pendingPause.mod.name)")
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
