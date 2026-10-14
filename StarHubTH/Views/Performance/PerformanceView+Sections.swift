import SwiftUI

/// Les sous-vues de `PerformanceView` qui ne portent pas d'état propre :
/// ancres, sélecteurs Avant/Après, carte « Détails et réglages », carte
/// « Autres outils de mesure », menu « Autres mesures… ». Sorties du fichier
/// principal pour tenir sous le plafond de 400 lignes (lot D).
extension PerformanceView {
    /// Tout saut programmé passe ici : `scrollTo` ne poste pas la
    /// notification de défilement d'AppKit, le retour en haut doit se
    /// remesurer (`scrollRecheck`).
    func jump(to id: String, _ proxy: ScrollViewProxy, animated: Bool = true) {
        withAnimation(reduceMotion || !animated ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .top) }
        scrollRecheck += 1
    }

    func navigation(_ proxy: ScrollViewProxy) -> some View {
        let comparisonAnchors = [("analysis", L10n.Performance.sectionAnalysis),
                                 ("game", L10n.Performance.inGameTitle)]
        let toolAnchors = (Self.toolAbsent(sloDiagnostic) ? [] : [("slo", L10n.PerformanceSloDiagnostic.title)])
            + (Self.toolAbsent(stardropiumDiagnostic) ? [] : [("stardropium", L10n.StardropiumMemory.title)])
        let anchors = [("summary", L10n.PerformanceEvidence.summary)]
            + (comparing ? comparisonAnchors : [])
            + [("loads", L10n.Performance.loadsTitle)] + toolAnchors
            + [("details", L10n.PerformanceEvidence.detailsCardTitle)]
        return ViewThatFits(in: .horizontal) {
            HStack {
                ForEach(anchors, id: \.0) { id, key in
                    Button(localization.L(key)) {
                        if id == "game" { comparing = true }
                        jump(to: id, proxy)
                    }.fixedSize().help(localization.L(key))
                }
            }
            Menu(localization.L(L10n.PerformanceEvidence.details)) {
                ForEach(anchors, id: \.0) { id, key in
                    Button(localization.L(key)) {
                        if id == "game" { comparing = true }
                        jump(to: id, proxy, animated: false)
                    }
                }
            }.fixedSize()
        }
    }

    /// « Autres mesures… » du bloc Mesurer : benchmark, puis les outils tiers
    /// vers leur carte (pleine si installés, sinon « Autres outils »).
    func otherMeasures(_ proxy: ScrollViewProxy) -> [(title: String, action: () -> Void)] {
        let scroll: (String) -> Void = { id in
            jump(to: id, proxy)
        }
        return [
            (localization.L(L10n.Benchmark.title), { openBenchmark(nil) }),
            (localization.L(L10n.PerformanceSloDiagnostic.title),
             { scroll(Self.toolAbsent(sloDiagnostic) ? "tools" : "slo") }),
            (localization.L(L10n.StardropiumMemory.title),
             { scroll(Self.toolAbsent(stardropiumDiagnostic) ? "tools" : "stardropium") }),
        ]
    }

    /// Le mod tiers n'est pas installé (ou se télécharge) : pas de carte
    /// pleine, une ligne dans « Autres outils de mesure ».
    static func toolAbsent(_ diagnostic: SloDiagnosticSessionStore) -> Bool {
        switch diagnostic.state {
        case .unavailable(.sloAbsent), .unavailable(.sloDownloading): return true
        default: return false
        }
    }

    var selectors: some View {
        WrapHStack(spacing: AppDesign.Spacing.md) {
            picker(L10n.Performance.before, selection: Binding(
                get: { store.beforeId }, set: { store.select(before: $0, after: store.afterId) }))
            picker(L10n.Performance.after, selection: Binding(
                get: { store.afterId }, set: { store.select(before: store.beforeId, after: $0) }))
        }
    }

    func picker(_ key: String, selection: Binding<String?>) -> some View {
        Picker(localization.L(key), selection: selection) {
            ForEach(store.sides) { side in
                Text(label(side)).tag(Optional(side.id))
            }
        }
        .frame(maxWidth: 360)
    }

    /// Date, durée, minutes comparables, nom de mesure (spec §3b).
    func label(_ side: ProbeSide) -> String {
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
