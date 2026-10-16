import SwiftUI

/// Pièces d'affichage des Alertes système, sorties de `SystemAlertsView`
/// (plafond de taille, audit UX 2026-10-16, I-T26).
struct SeverityBar: View {
    struct Segment: Equatable {
        let count: Int
        let color: Color
    }
    let segments: [Segment]

    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.count }, 1)
        let visible = segments.filter { $0.count > 0 }
        GeometryReader { geo in
            let gaps = CGFloat(max(visible.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, seg in
                    Capsule()
                        .fill(seg.color.gradient)
                        .frame(width: max(6, (geo.size.width - gaps) * CGFloat(seg.count) / CGFloat(total)))
                }
            }
        }
        .frame(height: 6)
        .animation(Motion.animation(.smooth), value: segments.map(\.count))
    }
}

/// Le glyphe de l'état « rien à signaler », qui s'installe en douceur à
/// l'arrivée (aucune animation sous « Réduire les animations »).
struct AllClearGlyph: View {
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle()
                .fill(AppDesign.Color.success.opacity(AppDesign.Opacity.light))
                .frame(width: 96, height: 96)
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: AppDesign.Font.scaled(44)))
                .foregroundStyle(AppDesign.Color.success.gradient)
        }
        .scaleEffect(shown ? 1 : 0.85)
        .opacity(shown ? 1 : 0)
        .onAppear { withMotion(.spring(duration: 0.5, bounce: 0.3)) { shown = true } }
        .accessibilityHidden(true)
    }
}
