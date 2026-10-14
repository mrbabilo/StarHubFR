import SwiftUI

/// « Depuis le lancement : N min » d'un diagnostic tiers (SLO, Stardropium)
/// en attente du jeu ou en session. Pas de durée restante : le diagnostic
/// finit quand le joueur quitte le jeu. `TimelineView` redessine seulement,
/// ne relit rien (piège `.periodic(from: .now)` + `.task(id:)`).
struct PerformanceDiagnosticElapsed: View {
    @ObservedObject var localization: LocalizationStore
    var store: SloDiagnosticSessionStore
    let kind: SloDiagnosticPresentationKind

    var body: some View {
        if kind == .waitingForGame || kind == .running {
            TimelineView(.everyMinute) { context in
                if let minutes = SloDiagnosticPresentation.elapsedMinutes(since: store.sessionSince, now: context.date) {
                    Text(String(format: localization.L(L10n.PerformanceSloDiagnostic.elapsed), Int64(minutes)))
                        .font(AppDesign.Font.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }
}
