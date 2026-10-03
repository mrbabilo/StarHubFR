import SwiftUI

/// D4-T4 §3b — l'onglet « Performances » : deux moments de jeu, ce qui a
/// changé, la fluidité, le coût par mod, l'analyse. Ne calcule rien : tout
/// vient de `ProbePerformanceStore` (Core, testé).
struct PerformanceView: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
                // D5-B — la carte « Chargements » en tête : sa comparaison est
                // automatique et ne dépend pas des sélecteurs Avant/Après plus
                // bas. Elle vit aussi en `.needTwo` (pas de paire de minutes).
                if store.status == .ready || store.status == .needTwo {
                    PerformanceCard { PerformanceLoadsSection(viewModel: viewModel, localization: localization, store: store) }
                } else if viewModel.benchmark.interrupted != nil {
                    // Benchmark interrompu : la reprise reste visible hors de la carte.
                    PerformanceBenchmarkStatus(runner: viewModel.benchmark, localization: localization)
                }
                PerformanceCard { PerformanceImpactSection(viewModel: viewModel, localization: localization) }
                PerformanceProbeSection(viewModel: viewModel, localization: localization)
                // En-tête, mesure guidée et sélecteurs forment un bloc : les
                // tuiles de trame lisent la paire choisie (`store.report`).
                inGameTitle
                PerformanceHeader(localization: localization, store: store)
                PerformanceGuidedBar(viewModel: viewModel, localization: localization, store: store)
                content
            }
            .padding(AppDesign.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { if store.status == .idle { await store.reload(gameDir: viewModel.gameDir) } }
        // L'onglet reste monté : relire à chaque retour, sinon une session
        // jouée depuis n'apparaît jamais (le cache taille + date de l'index
        // rend la relecture quasi gratuite quand rien n'a bougé).
        .onChange(of: viewModel.navigationStore.diagnosticsSegment) { _, segment in
            if segment == .performance { Task { await store.reload(gameDir: viewModel.gameDir) } }
        }
        // Jeu quitté : la session close entre dans les analyses sans attendre
        // un retour dans l'app.
        .onReceive(GameExit.publisher) { Task { await store.reload(gameDir: viewModel.gameDir) } }
        // Le jeu se joue app en arrière-plan, onglet ouvert : relire au retour
        // dans l'app, sinon la mesure démarrée n'entre jamais dans les sélecteurs.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if viewModel.navigationStore.diagnosticsSegment == .performance { Task { await store.reload(gameDir: viewModel.gameDir) } }
        }
    }

    private var inGameTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localization.L(L10n.Performance.inGameTitle)).font(AppDesign.Font.headline(.semibold))
            Text(localization.L(L10n.Performance.inGameSubtitle))
                .font(AppDesign.Font.footnote).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.status {
        case .idle, .loading:
            StateCard(icon: "hourglass", text: localization.L(L10n.Performance.loading), actionTitle: nil) {}
        case .noProbe:
            StateCard(icon: "gauge.with.dots.needle.0percent",
                      text: localization.L(L10n.Performance.noProbe), actionTitle: nil) {}
        case .needTwo:
            StateCard(icon: "square.split.2x1", text: localization.L(L10n.Performance.needTwo),
                      actionTitle: nil) {}
        case .ready:
            selectors
            if let report = store.report {
                PerformanceCard {
                    PerformanceChangesSection(viewModel: viewModel, localization: localization,
                                              report: report, configDiffs: store.configDiffs)
                }
                PerformanceCard { PerformanceSmoothnessSection(localization: localization, report: report) }
                PerformanceCard {
                    PerformanceCostsSection(viewModel: viewModel, localization: localization, report: report)
                }
                PerformanceCard {
                    PerformanceAnalysisSection(viewModel: viewModel, localization: localization,
                                               store: store, report: report)
                }
            }
            if store.unreadableLines > 0 {
                Text(String(format: localization.L(L10n.Performance.unreadable), store.unreadableLines))
                    .font(AppDesign.Font.footnote).foregroundColor(.secondary)
            }
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
}
