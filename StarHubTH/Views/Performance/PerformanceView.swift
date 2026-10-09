import SwiftUI

/// D4-T4 §3b — l'onglet « Performances » : deux moments de jeu, ce qui a
/// changé, la fluidité, le coût par mod, l'analyse. Ne calcule rien : tout
/// vient de `ProbePerformanceStore` (Core, testé).
struct PerformanceView: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    /// D2-T3 — l'état environnement de la session (carte « Environnement »),
    /// rechargé aux mêmes moments que la sonde.
    var environment: SessionEnvironmentStore
    var sloDiagnostic: SloDiagnosticSessionStore
    var stardropiumDiagnostic: SloDiagnosticSessionStore
    @State private var comparing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
                    navigation(proxy)
                    PerformanceMeasurementStatus(viewModel: viewModel, localization: localization, store: store)
                    PerformanceGuidedBar(viewModel: viewModel, localization: localization, store: store)
                    Picker(localization.L(L10n.Performance.inGameTitle), selection: $comparing) {
                        Text(localization.L(L10n.PerformanceEvidence.lastSession)).tag(false)
                        Text(localization.L(L10n.PerformanceEvidence.compare)).tag(true)
                    }.pickerStyle(.menu)
                    if comparing { selectors }
                    if store.isComputing { Text(localization.L(L10n.PerformanceEvidence.computing)).font(AppDesign.Font.footnote) }
                    PerformanceCard {
                        PerformanceSummarySection(localization: localization, report: comparing ? store.report : nil,
                                                  single: comparing ? nil : store.singleSummary)
                    }.id("summary")
                    PerformanceSloDiagnosticSection(
                        viewModel: viewModel, localization: localization,
                        store: sloDiagnostic, runtime: sloRuntime)
                        .id("slo")
                    if comparing, let report = store.report {
                        PerformanceCard {
                            PerformanceAnalysisSection(viewModel: viewModel, localization: localization,
                                                       store: store, report: report)
                        }.id("analysis")
                    }
                    if store.status == .ready || store.status == .needTwo {
                        PerformanceCard { PerformanceLoadsSection(viewModel: viewModel, localization: localization, store: store) }.id("loads")
                    } else if viewModel.benchmark.interrupted != nil {
                        PerformanceBenchmarkStatus(runner: viewModel.benchmark, localization: localization)
                    }
                    if comparing, let report = store.report {
                        PerformanceCard {
                            PerformanceChangesSection(viewModel: viewModel, localization: localization,
                                                      report: report, configDiffs: store.configDiffs)
                        }
                        PerformanceCard { PerformanceSmoothnessSection(localization: localization, report: report) }.id("game")
                        PerformanceCard { PerformanceCostsSection(viewModel: viewModel, localization: localization, report: report) }
                    }
                    PerformanceStardropiumMemorySection(viewModel: viewModel, localization: localization,
                                                       store: environment, diagnostic: stardropiumDiagnostic,
                                                       runtime: sloRuntime)
                        .id("stardropium")
                    PerformanceCard {
                        DisclosureGroup(localization.L(L10n.PerformanceEvidence.history)) {
                            PerformanceImpactSection(viewModel: viewModel, localization: localization)
                        }
                    }.id("mods")
                    PerformanceCard {
                        DisclosureGroup(localization.L(L10n.PerformanceTextures.title)) {
                            PerformanceTextureSection(viewModel: viewModel, localization: localization)
                        }
                    }.id("textures")
                    PerformanceCard {
                        DisclosureGroup(localization.L(L10n.Performance.envTitle)) {
                            PerformanceEnvironmentSection(localization: localization, store: environment)
                        }
                    }.id("details")
                    DisclosureGroup(localization.L(L10n.PerformanceEvidence.settings)) {
                        PerformanceProbeSection(viewModel: viewModel, localization: localization, store: store)
                    }
                    if store.unreadableLines > 0 {
                        Text(String(format: localization.L(L10n.Performance.unreadable), store.unreadableLines))
                            .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(AppDesign.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            await refreshSlo(resume: true)
            if store.status == .idle { await store.reload(gameDir: viewModel.gameDir) }
            if environment.status == .idle { await environment.reload(mods: viewModel.mods, gameDir: viewModel.gameDir) }
        }
        // L'onglet reste monté : relire à chaque retour, sinon une session
        // jouée depuis n'apparaît jamais (le cache taille + date de l'index
        // rend la relecture quasi gratuite quand rien n'a bougé).
        .onChange(of: viewModel.navigationStore.diagnosticsSegment) { _, segment in
            if segment == .performance {
                Task {
                    await refreshSlo(resume: true)
                    await store.reload(gameDir: viewModel.gameDir)
                    await environment.reload(mods: viewModel.mods, gameDir: viewModel.gameDir)
                }
            }
        }
        .onChange(of: viewModel.mods) { _, _ in
            guard viewModel.navigationStore.diagnosticsSegment == .performance else { return }
            Task { await refreshSlo(resume: false) }
        }
        // Jeu quitté : la session close entre dans les analyses — mais
        // seulement si l'onglet est affiché ; caché, quinze mutations
        // feraient re-rendre huit graphiques invisibles. L'ouverture de
        // l'onglet relit de toute façon (`onChange` ci-dessus).
        .onReceive(GameExit.publisher) {
            guard viewModel.navigationStore.diagnosticsSegment == .performance else { return }
            Task {
                await sloDiagnostic.gameExited(runtime: sloRuntime())
                await stardropiumDiagnostic.gameExited(runtime: sloRuntime())
                await store.reload(gameDir: viewModel.gameDir)
                await environment.reload(mods: viewModel.mods, gameDir: viewModel.gameDir)
            }
        }
        // Le jeu se joue app en arrière-plan, onglet ouvert : relire au retour
        // dans l'app, sinon la mesure démarrée n'entre jamais dans les sélecteurs.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if viewModel.navigationStore.diagnosticsSegment == .performance {
                Task {
                    await refreshSlo(resume: true)
                    await store.reload(gameDir: viewModel.gameDir)
                    await environment.reload(mods: viewModel.mods, gameDir: viewModel.gameDir)
                }
            }
        }
    }

    private func navigation(_ proxy: ScrollViewProxy) -> some View {
        let comparisonAnchors = [("analysis", L10n.Performance.sectionAnalysis),
                                 ("game", L10n.Performance.inGameTitle)]
        let anchors = [("summary", L10n.PerformanceEvidence.summary),
                       ("slo", L10n.PerformanceSloDiagnostic.title)]
            + (comparing ? comparisonAnchors : [])
            + [("loads", L10n.Performance.loadsTitle), ("stardropium", L10n.StardropiumMemory.title), ("mods", L10n.PerformanceEvidence.history),
               ("details", L10n.PerformanceEvidence.details)]
        return ViewThatFits(in: .horizontal) {
            HStack {
                ForEach(anchors, id: \.0) { id, key in
                    Button(localization.L(key)) {
                        if id == "game" { comparing = true }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .top) }
                    }.fixedSize().help(localization.L(key))
                }
            }
            Menu(localization.L(L10n.PerformanceEvidence.details)) {
                ForEach(anchors, id: \.0) { id, key in
                    Button(localization.L(key)) {
                        if id == "game" { comparing = true }
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }.fixedSize()
        }
    }

    private var selectors: some View {
        WrapHStack(spacing: AppDesign.Spacing.md) {
            picker(L10n.Performance.before, selection: Binding(
                get: { store.beforeId }, set: { store.select(before: $0, after: store.afterId) }))
            picker(L10n.Performance.after, selection: Binding(
                get: { store.afterId }, set: { store.select(before: store.beforeId, after: $0) }))
        }
    }

    private func picker(_ key: String, selection: Binding<String?>) -> some View {
        Picker(localization.L(key), selection: selection) {
            ForEach(store.sides) { side in
                Text(label(side)).tag(Optional(side.id))
            }
        }
        .frame(maxWidth: 360)
    }

    /// Date, durée, minutes comparables, nom de mesure (spec §3b).
    private func label(_ side: ProbeSide) -> String {
        let date = side.start.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "?"
        let duration = side.start.flatMap { start in side.end.map { end in
            Duration.seconds(end.timeIntervalSince(start))
                .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        } } ?? "?"
        let count = side.comparable.kept.count
        if let measurement = side.measurement {
            return String(format: localization.L(L10n.Performance.sideMeasurement),
                          measurement.name, duration, count)
        }
        return String(format: localization.L(L10n.Performance.sideSegment), date, duration, count)
    }

    private func refreshSlo(resume: Bool) async {
        let game = URL(fileURLWithPath: viewModel.gameDir)
        if resume {
            await sloDiagnostic.resumeIfNeeded(mods: viewModel.mods, gameDir: game,
                                               runtime: sloRuntime())
        }
        await sloDiagnostic.reload(mods: viewModel.mods, gameDir: game, runtime: sloRuntime())
        if resume {
            await stardropiumDiagnostic.resumeIfNeeded(mods: viewModel.mods, gameDir: game, runtime: sloRuntime())
        }
        await stardropiumDiagnostic.reload(mods: viewModel.mods, gameDir: game, runtime: sloRuntime())
    }

    private func sloRuntime() -> SloDiagnosticRuntime {
        let gameDir = viewModel.gameDir
        let modsRoot = URL(fileURLWithPath: gameDir).appendingPathComponent("Mods")
        return SloDiagnosticRuntime(
            modsRootURL: modsRoot,
            isGameRunning: { viewModel.isGameRunning() },
            busyReason: {
                SloDiagnosticExclusion.busyReason(
                    gameRunning: viewModel.isGameRunning(),
                    benchmarkActive: viewModel.benchmark.isActive
                        || viewModel.benchmark.interrupted != nil,
                    bisectionActive: viewModel.bisection.state != nil
                        || viewModel.bisection.isApplying
                        || viewModel.bisection.interruptedSnapshot != nil,
                    guidedPlanPending: store.plan != nil,
                    otherReason: viewModel.bulkToggleProgress != nil
                        || viewModel.isApplyingProfile
                        || viewModel.unresolvedApplyJournal != nil ? "mods-busy" : nil)
            },
            launchProfile: {
                UserDefaults.standard.string(forKey: UDKey.launchProfile) ?? "SMAPI"
            },
            modEnabled: { name in
                DiagnosticModToggle.enabled(root: name,
                    modsRoot: modsRoot)
            },
            setModEnabled: { name, enabled in
                guard !viewModel.isGameRunning() else { return false }
                let success = DiagnosticModToggle.setEnabled(enabled, root: name,
                    modsRoot: modsRoot)
                if success, viewModel.gameDir == gameDir {
                    // Publish exact activation before launch (ProbeLoadOrder reads this list).
                    viewModel.scanStore.setMods(TogglePlan.flipped(viewModel.mods,
                        folders: [name], target: enabled))
                }
                return success
            },
            grantOwnerWriteAccess: { ModZipInstaller.grantOwnerWriteAccess(in: $0) },
            launchGame: {
                guard viewModel.gameDir == gameDir,
                      UserDefaults.standard.string(forKey: UDKey.launchProfile) != "Vanilla" else { return false }
                return viewModel.launchGame(honoringCloseAfterLaunch: false)
            },
            rescan: {
                if viewModel.gameDir == gameDir { await viewModel.rescanInBackground() } // X125
            })
    }
}
