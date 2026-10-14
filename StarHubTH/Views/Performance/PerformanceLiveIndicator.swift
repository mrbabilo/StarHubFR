import AppKit
import SwiftUI

/// Pendant une mesure (plan guidé ou série pilotée, jeu ouvert), les chiffres
/// se relisent toutes les 15 s : un point qui pulse, « En direct » et l'âge de
/// la dernière relecture le disent ; jeu en arrière-plan, « En pause » et, en
/// pilotage, le bouton qui ramène le jeu devant (les minutes ne comptent que
/// fenêtre active). Rendu dans `PerformanceStatusLine`, jamais seul.
struct PerformanceLiveIndicator: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    /// Pilotage : proposer « Ramener le jeu » quand il est derrière.
    var offersBringGameFront = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Affichage seul : la seconde qui passe ne relit rien.
        TimelineView(.periodic(from: .distantPast, by: 1)) { context in
            let paused = !Self.gameIsFrontmost
            HStack(spacing: AppDesign.Spacing.xs) {
                if paused {
                    Circle().fill(AppDesign.Color.warning).frame(width: 8, height: 8)
                    Text(localization.L(L10n.PerformanceEvidence.livePaused)).fontWeight(.semibold)
                    if offersBringGameFront {
                        Button(localization.L(L10n.PerformancePilot.bringGameFront)) {
                            _ = GuidedPilotLive.bringGameToFront()
                        }
                        .controlSize(.small).clickableCursor()
                    }
                } else {
                    pulsingDot
                    Text(localization.L(L10n.PerformanceEvidence.live)).fontWeight(.semibold)
                    Text("· " + age(at: context.date)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .help(localization.L(paused ? L10n.PerformanceEvidence.livePausedHint
                                        : L10n.PerformanceEvidence.liveHint))
        }
        .font(AppDesign.Font.footnote)
        .accessibilityElement(children: .combine)
    }

    /// Jeu en arrière-plan (l'onglet regardé, par exemple) : la sonde écarte
    /// toute minute sans focus, rien de neuf n'arrive avant son retour.
    static var gameIsFrontmost: Bool {
        GameProcess.isGame(localizedName: NSWorkspace.shared.frontmostApplication?.localizedName)
    }

    @ViewBuilder private var pulsingDot: some View {
        let dot = Circle().fill(AppDesign.Color.success).frame(width: 8, height: 8)
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
                .stroke(AppDesign.Color.success.opacity(on ? 0.7 : 0), lineWidth: 2))
        } animation: { on in on ? .easeOut(duration: 0.25) : .easeIn(duration: 1.2) }
    }
}
