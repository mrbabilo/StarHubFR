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
                PerformanceHeader(viewModel: viewModel, localization: localization, store: store)
                content
            }
            .padding(AppDesign.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { if store.status == .idle { await store.reload() } }
        // L'onglet reste monté : relire à chaque retour, sinon une session
        // jouée depuis n'apparaît jamais (le cache taille + date de l'index
        // rend la relecture quasi gratuite quand rien n'a bougé).
        .onChange(of: viewModel.navigationStore.diagnosticsSegment) { _, segment in
            if segment == .performance { Task { await store.reload() } }
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
                PerformanceChangesSection(viewModel: viewModel, localization: localization,
                                          report: report, configsDirectory: store.configsDirectory)
                PerformanceSmoothnessSection(localization: localization, report: report)
                PerformanceCostsSection(viewModel: viewModel, localization: localization, report: report)
                PerformanceAnalysisSection(viewModel: viewModel, localization: localization,
                                           store: store, report: report)
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
