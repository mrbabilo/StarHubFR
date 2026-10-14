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
    @State var comparing = false
    /// Une seule feuille de benchmark pour l'onglet (chargements, analyse) :
    /// le dossier pré-rempli s'efface à la fermeture — rouverte du bouton
    /// générique, elle repart vierge (Review Focus 5).
    @State private var showBenchmark = false
    @State private var benchmarkPrefill: String?
    /// « Sonde et réglages », en bas : déplié par le lien de la ligne sonde.
    @State var settingsExpanded = false
    @State var historyExpanded = false
    /// Le mod à mettre en tête de l'historique (arrivée depuis la liste, la fiche).
    @State var historyFocus: String?
    /// La session la plus récente lue à la dernière visite : une plus
    /// récente à cette visite se signale (lot D, G9).
    @State private var lastSeenSession: String?
    /// La rangée d'ancres est sortie de l'écran : le retour en haut s'affiche.
    @State private var scrolledPastTop = false
    /// Incrémenté à chaque saut programmé : le retour en haut se remesure.
    @State var scrollRecheck = 0
    @AppStorage(UDKey.probeLoadEarlyConsent) var loadEarlyConsent: Bool?
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
                    navigation(proxy).backToTopMarker(scrolledPast: $scrolledPastTop, recheck: scrollRecheck) { viewModel.log($0) }
                    PerformanceMeasurementStatus(viewModel: viewModel, localization: localization, store: store) {
                        settingsExpanded = true
                        jump(to: "settings", proxy)
                    }
                    PerformanceStatusLine(viewModel: viewModel, localization: localization, store: store,
                                          sloDiagnostic: sloDiagnostic, stardropiumDiagnostic: stardropiumDiagnostic)
                    PerformancePilotStatus(viewModel: viewModel, localization: localization, store: store) { scroll in
                        comparing = true
                        if scroll { jump(to: "summary", proxy, animated: false) }
                    }
                    PerformanceGuidedBar(viewModel: viewModel, localization: localization, store: store,
                                         otherMeasures: otherMeasures(proxy))
                    Picker(localization.L(L10n.Performance.inGameTitle), selection: $comparing) {
                        Text(localization.L(L10n.PerformanceEvidence.lastSession)).tag(false)
                        Text(localization.L(L10n.PerformanceEvidence.compare)).tag(true)
                    }.pickerStyle(.menu)
                    if comparing { selectors }
                    if let newest = newestSide, let seen = lastSeenSession, newest.session != seen {
                        Label(String(format: localization.L(L10n.Performance.newSessionLine),
                                     PerformanceMetricText.source(newest)), systemImage: "sparkles")
                            .font(AppDesign.Font.footnote(.semibold))
                    }
                    let live = PerformanceStatusLine.isLive(viewModel, store)
                    PerformanceCard {
                        PerformanceSummarySection(localization: localization, report: comparing ? store.report : nil,
                                                  single: comparing ? nil : store.singleSummary,
                                                  probeInstalled: probeInstalled)
                    }.liveRefreshFlash(live ? store.lastLoadedAt : nil, reduceMotion: reduceMotion).id("summary")
                    if !comparing, store.sides.count >= 2 {
                        PerformanceCard {
                            SplitRow {
                                Text(localization.L(L10n.Performance.analysisSingleHint))
                                    .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                            } trailing: {
                                Button(localization.L(L10n.PerformanceEvidence.compare)) { comparing = true }
                                    .buttonStyle(.bordered).controlSize(.small).clickableCursor()
                            }
                        }
                    }
                    if comparing, let report = store.report {
                        PerformanceCard {
                            PerformanceAnalysisSection(viewModel: viewModel, localization: localization,
                                                       store: store, report: report,
                                                       onBenchmark: { openBenchmark($0) })
                        }.id("analysis")
                    }
                    // Lot A (S4) : la carte vit dès que le store a lu, sonde ou
                    // pas — le benchmark n'exige que la sonde, pas une session.
                    if store.status != .idle && store.status != .loading {
                        PerformanceCard {
                            PerformanceLoadsSection(viewModel: viewModel, localization: localization, store: store,
                                                    openBenchmark: { openBenchmark($0) })
                        }.id("loads")
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
                    // Lot B (S3) : les outils tiers n'ont une carte pleine que
                    // s'ils sont installés, et après les mesures de la sonde ;
                    // absents, une ligne chacun dans « Autres outils », repliée.
                    if !Self.toolAbsent(sloDiagnostic) {
                        PerformanceSloDiagnosticSection(
                            viewModel: viewModel, localization: localization,
                            store: sloDiagnostic, runtime: sloRuntime)
                            .id("slo")
                    }
                    if !Self.toolAbsent(stardropiumDiagnostic) {
                        PerformanceStardropiumMemorySection(viewModel: viewModel, localization: localization,
                                                           store: environment, diagnostic: stardropiumDiagnostic,
                                                           runtime: sloRuntime)
                            .id("stardropium")
                    }
                    detailsCard
                    toolsCard
                    if store.unreadableLines > 0 {
                        Text(String(format: localization.L(L10n.Performance.unreadable), store.unreadableLines))
                            .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(AppDesign.Spacing.lg)
                // Place pour le retour en haut : il ne couvre pas la dernière carte.
                .padding(.bottom, AppDesign.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .bottomTrailing) {
                if scrolledPastTop {
                    BackToTopButton(title: localization.L(L10n.Performance.backToTop)) {
                        jump(to: BackToTop.anchor, proxy)
                    }
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: scrolledPastTop)
            .onAppear { consumeFocus(proxy) }
            .onChange(of: viewModel.navigationStore.pendingPerformanceFocus) { _, _ in consumeFocus(proxy) }
        }
        .sheet(isPresented: $showBenchmark, onDismiss: { benchmarkPrefill = nil }) {
            PerformanceBenchmarkSheet(viewModel: viewModel, localization: localization,
                                      isPresented: $showBenchmark, prefilledPause: benchmarkPrefill)
        }
        .task {
            await PerformanceReloadLog.run(viewModel, cause: "ouverture de l'onglet") {
                await refreshSlo(resume: true)
                if store.status == .idle { await store.reload(gameDir: viewModel.gameDir) }
                if environment.status == .idle { await environment.reload(mods: viewModel.mods, gameDir: viewModel.gameDir) }
            }
        }
        // L'onglet reste monté : relire à chaque retour, sinon une session
        // jouée depuis n'apparaît jamais (le cache taille + date de l'index
        // rend la relecture quasi gratuite quand rien n'a bougé).
        .onChange(of: viewModel.navigationStore.diagnosticsSegment) { _, segment in
            if segment == .performance {
                Task { await reloadAll(cause: "retour sur l'onglet") }
            } else {
                lastSeenSession = newestSide?.session
            }
        }
        .onChange(of: store.lastLoadedAt) { _, _ in
            if lastSeenSession == nil { lastSeenSession = newestSide?.session }
        }
        .onChange(of: viewModel.mods) { _, _ in
            guard viewModel.navigationStore.diagnosticsSegment == .performance else { return }
            Task {
                await PerformanceReloadLog.run(viewModel, cause: "parc modifié, diagnostics SLO seuls") {
                    await refreshSlo(resume: false)
                }
            }
        }
        // Jeu quitté : la session close entre dans les analyses — mais
        // seulement si l'onglet est affiché ; caché, quinze mutations
        // feraient re-rendre huit graphiques invisibles. L'ouverture de
        // l'onglet relit de toute façon (`onChange` ci-dessus).
        .onReceive(GameExit.publisher) {
            guard viewModel.navigationStore.diagnosticsSegment == .performance else { return }
            Task {
                await PerformanceReloadLog.run(viewModel, cause: "fermeture du jeu") {
                    await sloDiagnostic.gameExited(runtime: sloRuntime())
                    await stardropiumDiagnostic.gameExited(runtime: sloRuntime())
                    await store.reload(gameDir: viewModel.gameDir)
                    await environment.reload(mods: viewModel.mods, gameDir: viewModel.gameDir)
                }
            }
        }
        // Le jeu se joue app en arrière-plan, onglet ouvert : relire au retour
        // dans l'app, sinon la mesure démarrée n'entre jamais dans les sélecteurs.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if viewModel.navigationStore.diagnosticsSegment == .performance {
                Task { await reloadAll(cause: "retour dans l'app") }
            }
        }
    }

    private var newestSide: ProbeSide? {
        store.sides.max { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    /// L'intention posée par `NavigationStore.openPerformance` : déplier,
    /// mettre le mod en tête, défiler. Consommée ici, jamais avant le
    /// changement d'onglet (piège MainView).
    private func consumeFocus(_ proxy: ScrollViewProxy) {
        guard let focus = viewModel.navigationStore.pendingPerformanceFocus else { return }
        viewModel.navigationStore.pendingPerformanceFocus = nil
        if focus.anchor == "mods" {
            historyExpanded = true
            historyFocus = focus.modFolder
        }
        // Après le rendu qui déplie : l'ancre doit exister pour être atteinte.
        Task { @MainActor in
            jump(to: focus.anchor, proxy)
        }
    }

    private var probeInstalled: Bool {
        if case .absent = ModPresence.resolve(uniqueId: ModPresence.probeId, in: viewModel.mods) { return false }
        return true
    }

    /// Lot B (S7) : quatre volets repliés sous une seule carte.
    private var detailsCard: some View {
        PerformanceCard {
            Text(localization.L(L10n.PerformanceEvidence.detailsCardTitle))
                .font(AppDesign.Font.headline(.semibold))
            DisclosureGroup(localization.L(L10n.PerformanceEvidence.history), isExpanded: $historyExpanded) {
                PerformanceImpactSection(viewModel: viewModel, localization: localization, focus: historyFocus)
            }.id("mods")
            Divider()
            DisclosureGroup(localization.L(L10n.PerformanceTextures.title)) {
                PerformanceTextureSection(viewModel: viewModel, localization: localization)
            }.id("textures")
            Divider()
            DisclosureGroup(localization.L(L10n.Performance.envTitle)) {
                PerformanceEnvironmentSection(localization: localization, store: environment)
            }
            Divider()
            DisclosureGroup(localization.L(L10n.PerformanceEvidence.settings), isExpanded: $settingsExpanded) {
                PerformanceProbeSection(viewModel: viewModel, localization: localization, store: store,
                                        loadOrderBannerHoisted: PerformanceMeasurementStatus.hoistsLoadOrderBanner(
                                            viewModel, store, consent: loadEarlyConsent))
            }.id("settings")
        }.id("details")
    }

    /// Lot B (S3) : les outils tiers absents, une ligne chacun, repliés.
    @ViewBuilder
    private var toolsCard: some View {
        if Self.toolAbsent(sloDiagnostic) || Self.toolAbsent(stardropiumDiagnostic) {
            PerformanceCard {
                DisclosureGroup(localization.L(L10n.PerformanceEvidence.toolsCardTitle)) {
                    VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                        if Self.toolAbsent(sloDiagnostic) {
                            PerformanceSloDiagnosticSection(
                                viewModel: viewModel, localization: localization,
                                store: sloDiagnostic, runtime: sloRuntime, compact: true)
                        }
                        if Self.toolAbsent(stardropiumDiagnostic) {
                            PerformanceStardropiumDiagnosticControls(
                                viewModel: viewModel, localization: localization,
                                store: stardropiumDiagnostic, runtime: sloRuntime, compact: true)
                        }
                    }.padding(.top, AppDesign.Spacing.sm)
                }
            }.id("tools")
        }
    }

    private func reloadAll(cause: String) async {
        await PerformanceReloadLog.run(viewModel, cause: cause) {
            await refreshSlo(resume: true)
            await store.reload(gameDir: viewModel.gameDir)
            await environment.reload(mods: viewModel.mods, gameDir: viewModel.gameDir)
        }
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

    func openBenchmark(_ pauseFolder: String?) {
        benchmarkPrefill = pauseFolder
        showBenchmark = true
    }

    func sloRuntime() -> SloDiagnosticRuntime {
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
                        || viewModel.unresolvedApplyJournal != nil ? "mods-busy" : nil,
                    pilotActive: viewModel.pilot.busyReasonKey != nil)
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
                    // F3 — `healthIssues` est mise en cache : un toggle hors
                    // VM doit la recalculer (même règle que le VM).
                    viewModel.recomputeHealthIssues()
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
