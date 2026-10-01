import SwiftUI

/// D5-C — l'étoile à cinq branches. Rayon = √part (les petits mods restent
/// visibles) ; anneaux de repère à 1 %, 10 % et 50 % du total. Une branche
/// non mesurée est en pointillés, avec « — ». Swift Charts n'a pas de radar :
/// dessin à la main.
struct ModImpactRadar: View {
    let shares: [ModImpactAxis: Double]
    let size: CGFloat
    var showsLabels = true
    let label: (ModImpactAxis) -> String
    /// Infobulle et libellé VoiceOver d'une branche.
    let detail: (ModImpactAxis) -> String

    private static let rings: [Double] = [0.01, 0.1, 0.5]
    private var axes: [ModImpactAxis] { ModImpactAxis.allCases }
    /// Avec libellés, le dessin occupe 60 % : la place des textes autour.
    private var radius: CGFloat { size / 2 * (showsLabels ? 0.6 : 0.95) }

    private func point(_ index: Int, _ fraction: Double, center: CGPoint) -> CGPoint {
        let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(axes.count)
        return CGPoint(x: center.x + radius * fraction * cos(angle), y: center.y + radius * fraction * sin(angle))
    }

    var body: some View {
        ZStack {
            Canvas { context, canvas in
                let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let grid = GraphicsContext.Shading.color(.secondary.opacity(AppDesign.Opacity.strong))
                for ring in Self.rings + [1] {
                    var path = Path()
                    for i in axes.indices {
                        let p = point(i, ring.squareRoot(), center: center)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    path.closeSubpath()
                    context.stroke(path, with: grid, lineWidth: 0.5)
                }
                for (i, axis) in axes.enumerated() {
                    var spoke = Path()
                    spoke.move(to: center)
                    spoke.addLine(to: point(i, 1, center: center))
                    context.stroke(spoke, with: grid,
                                   style: StrokeStyle(lineWidth: 0.5, dash: shares[axis] == nil ? [2, 2] : []))
                }
                var shape = Path()
                for (i, axis) in axes.enumerated() {
                    let p = point(i, min(1, (shares[axis] ?? 0).squareRoot()), center: center)
                    if i == 0 { shape.move(to: p) } else { shape.addLine(to: p) }
                }
                shape.closeSubpath()
                context.fill(shape, with: .color(AppDesign.Color.accent.opacity(AppDesign.Opacity.medium)))
                context.stroke(shape, with: .color(AppDesign.Color.accent), lineWidth: showsLabels ? 1.5 : 1)
            }
            if showsLabels {
                ForEach(Array(axes.enumerated()), id: \.element) { i, axis in
                    Text(shares[axis] == nil ? "\(label(axis)) —" : label(axis))
                        .font(AppDesign.Font.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: size * 0.36)
                        .frame(minWidth: 18, minHeight: 18)
                        .contentShape(.rect)
                        .help(detail(axis))
                        .position(point(i, 1.38, center: CGPoint(x: size / 2, y: size / 2)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(axes.map(detail).joined(separator: ". "))
    }
}
