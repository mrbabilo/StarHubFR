import SwiftUI

/// Pendant une mesure (plan guidé ou série pilotée, jeu ouvert), les chiffres
/// se relisent toutes les 15 s : un point qui pulse, « En direct » et l'âge de
/// la dernière relecture le disent. Hors mesure, seule la ligne « Actualisation
/// en cours » reste, sa place toujours réservée pour que le texte ne saute pas.
struct PerformanceLiveIndicator: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isLive {
            HStack(spacing: AppDesign.Spacing.xs) {
                pulsingDot
                Text(localization.L(L10n.PerformanceEvidence.live)).fontWeight(.semibold)
                // Affichage seul : la seconde qui passe ne relit rien.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("· " + age(at: context.date)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .font(AppDesign.Font.footnote)
            .help(localization.L(L10n.PerformanceEvidence.liveHint))
            .accessibilityElement(children: .combine)
        } else {
            Text(localization.L(L10n.PerformanceEvidence.computing)).font(AppDesign.Font.footnote)
                .opacity(store.isComputing ? 1 : 0).accessibilityHidden(!store.isComputing)
        }
    }

    /// Même règle que la minuterie de relecture (`PerformanceMeasurementStatus`).
    var isLive: Bool { (store.plan != nil || viewModel.pilot.isActive) && viewModel.isGameRunning() }

    @ViewBuilder private var pulsingDot: some View {
        let dot = Circle().fill(Color.green).frame(width: 8, height: 8)
        if reduceMotion {
            dot
        } else {
            dot.phaseAnimator([false, true]) { view, on in
                view.opacity(on ? 1 : 0.35).scaleEffect(on ? 1 : 0.7)
            } animation: { _ in .easeInOut(duration: 0.8) }
        }
    }

    private func age(at now: Date) -> String {
        guard !store.isComputing, let last = store.lastLoadedAt else {
            return localization.L(L10n.PerformanceEvidence.liveRefreshing)
        }
        return String(format: localization.L(L10n.PerformanceEvidence.liveUpdated),
                      Int64(max(0, now.timeIntervalSince(last))))
    }
}

extension View {
    /// Un liseré qui s'allume puis s'éteint à chaque relecture en direct : les
    /// chiffres de la carte viennent de changer. Rien sans mouvement autorisé.
    func liveRefreshFlash(_ trigger: Date?, reduceMotion: Bool) -> some View {
        phaseAnimator([false, true], trigger: reduceMotion ? nil : trigger) { view, on in
            view.overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.lg, style: .continuous)
                .stroke(Color.green.opacity(on ? 0.7 : 0), lineWidth: 2))
        } animation: { on in on ? .easeOut(duration: 0.25) : .easeIn(duration: 1.2) }
    }
}
