import SwiftUI

struct SaveFarmGlyph: View, Equatable {
    let whichFarm: Int
    let modFarmName: String?
    let size: CGSize

    init(whichFarm: Int, modFarmName: String?, size: CGSize = CGSize(width: 80, height: 56)) {
        self.whichFarm = whichFarm
        self.modFarmName = modFarmName
        self.size = size
    }

    var body: some View {
        Group {
            switch whichFarm {
            case 0: StandardFarmGlyph(size: size)
            case 1: RiverlandFarmGlyph(size: size)
            case 2: ForestFarmGlyph(size: size)
            case 3: HilltopFarmGlyph(size: size)
            case 4: WildernessFarmGlyph(size: size)
            case 5: FourCornersFarmGlyph(size: size)
            case 6: BeachFarmGlyph(size: size)
            case 7: MeadowlandsFarmGlyph(size: size)
            default: ModFarmGlyph(sfSymbol: Self.farmIcon(for: whichFarm), size: size)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.whichFarm == rhs.whichFarm
            && lhs.modFarmName == rhs.modFarmName
            && lhs.size == rhs.size
    }

    private static func farmIcon(for whichFarm: Int) -> String {
        switch whichFarm {
        case 0: return "leaf.fill"
        case 1: return "water.waves"
        case 2: return "tree.fill"
        case 3: return "mountain.2.fill"
        case 4: return "moon.stars.fill"
        case 5: return "square.grid.2x2.fill"
        case 6: return "sun.max.fill"
        case 7: return "pawprint.fill"
        default: return "questionmark.square.fill"
        }
    }
}

private struct StandardFarmGlyph: View {
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                .fill(SaveFarmPalette.standardBg)

            VStack(spacing: 2) {
                ZStack(alignment: .bottom) {
                    Path { p in
                        p.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.50))
                        p.addLine(to: CGPoint(x: size.width * 0.50, y: size.height * 0.20))
                        p.addLine(to: CGPoint(x: size.width * 0.82, y: size.height * 0.50))
                        p.closeSubpath()
                    }
                    .fill(SaveFarmPalette.standardAccent)

                    Rectangle()
                        .fill(SaveFarmPalette.standardAccent)
                        .frame(width: size.width * 0.42, height: size.height * 0.30)
                }
                .frame(height: size.height * 0.50)

                VStack(spacing: 2) {
                    furrow(at: 0.30)
                    furrow(at: 0.46)
                    furrow(at: 0.62)
                }
            }
            .padding(AppDesign.Spacing.xs)
        }
    }

    private func furrow(at y: CGFloat) -> some View {
        Rectangle()
            .fill(SaveFarmPalette.standardAccent.opacity(AppDesign.Opacity.strong))
            .frame(width: size.width * 0.60, height: 1)
            .position(x: size.width * 0.50, y: size.height * y)
    }
}

private struct RiverlandFarmGlyph: View {
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                .fill(SaveFarmPalette.riverlandBg)

            Path { p in
                p.move(to: CGPoint(x: 0, y: size.height * 0.45))
                p.addCurve(
                    to: CGPoint(x: size.width, y: size.height * 0.55),
                    control1: CGPoint(x: size.width * 0.30, y: size.height * 0.25),
                    control2: CGPoint(x: size.width * 0.70, y: size.height * 0.75)
                )
                p.addLine(to: CGPoint(x: size.width, y: size.height * 0.70))
                p.addCurve(
                    to: CGPoint(x: 0, y: size.height * 0.60),
                    control1: CGPoint(x: size.width * 0.70, y: size.height * 0.85),
                    control2: CGPoint(x: size.width * 0.30, y: size.height * 0.35)
                )
                p.closeSubpath()
            }
            .fill(SaveFarmPalette.riverlandAccent.opacity(AppDesign.Opacity.strong))

            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(SaveFarmPalette.riverlandBg.opacity(AppDesign.Opacity.secondary))
                    .frame(width: 10, height: 10)
                    .position(
                        x: size.width * [0.22, 0.40, 0.60, 0.78][i],
                        y: size.height * [0.25, 0.80, 0.20, 0.78][i]
                    )
            }
        }
    }
}

private struct ForestFarmGlyph: View {
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                .fill(SaveFarmPalette.forestBg)

            Circle()
                .fill(SaveFarmPalette.forestAccent.opacity(AppDesign.Opacity.medium))
                .frame(width: size.width * 0.40, height: size.width * 0.40)
                .position(x: size.width * 0.50, y: size.height * 0.55)

            ForEach(0..<3, id: \.self) { i in
                let xs: [CGFloat] = [0.28, 0.55, 0.80]
                Path { p in
                    p.move(to: CGPoint(x: size.width * xs[i], y: size.height * 0.78))
                    p.addLine(to: CGPoint(x: size.width * (xs[i] + 0.10), y: size.height * 0.22))
                    p.addLine(to: CGPoint(x: size.width * (xs[i] + 0.20), y: size.height * 0.78))
                    p.closeSubpath()
                }
                .fill(SaveFarmPalette.forestAccent)
            }
        }
    }
}

private struct HilltopFarmGlyph: View {
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                .fill(SaveFarmPalette.hilltopBg)

            Path { p in
                p.move(to: CGPoint(x: size.width * 0.05, y: size.height * 0.78))
                p.addLine(to: CGPoint(x: size.width * 0.50, y: size.height * 0.30))
                p.addLine(to: CGPoint(x: size.width * 0.95, y: size.height * 0.78))
                p.closeSubpath()
            }
            .fill(SaveFarmPalette.hilltopAccent.opacity(AppDesign.Opacity.light))

            ForEach(0..<3, id: \.self) { i in
                let xs: [CGFloat] = [0.30, 0.50, 0.70]
                let ys: [CGFloat] = [0.52, 0.42, 0.55]
                RoundedRectangle(cornerRadius: 1)
                    .fill(SaveFarmPalette.hilltopAccent)
                    .frame(width: 4, height: 4)
                    .position(x: size.width * xs[i], y: size.height * ys[i])
            }
        }
    }
}

private struct WildernessFarmGlyph: View {
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                .fill(SaveFarmPalette.wildernessBg)

            Circle()
                .fill(SaveFarmPalette.wildernessAccent)
                .frame(width: 16, height: 16)
                .position(x: size.width * 0.78, y: size.height * 0.25)

            ForEach(0..<3, id: \.self) { i in
                let xs: [CGFloat] = [0.20, 0.45, 0.68]
                Path { p in
                    p.move(to: CGPoint(x: size.width * xs[i], y: size.height * 0.78))
                    p.addLine(to: CGPoint(x: size.width * (xs[i] + 0.12), y: size.height * 0.40))
                    p.addLine(to: CGPoint(x: size.width * (xs[i] + 0.24), y: size.height * 0.78))
                    p.closeSubpath()
                }
                .fill(SaveFarmPalette.wildernessAccent.opacity(AppDesign.Opacity.disabled))
            }
        }
    }
}

private struct FourCornersFarmGlyph: View {
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                .fill(SaveFarmPalette.fourCornersBg)

            Path { p in
                p.move(to: CGPoint(x: size.width * 0.46, y: size.height * 0.22))
                p.addLine(to: CGPoint(x: size.width * 0.54, y: size.height * 0.22))
                p.addLine(to: CGPoint(x: size.width * 0.54, y: size.height * 0.78))
                p.addLine(to: CGPoint(x: size.width * 0.46, y: size.height * 0.78))
                p.closeSubpath()
                p.move(to: CGPoint(x: size.width * 0.22, y: size.height * 0.46))
                p.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.46))
                p.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.54))
                p.addLine(to: CGPoint(x: size.width * 0.22, y: size.height * 0.54))
                p.closeSubpath()
            }
            .fill(SaveFarmPalette.fourCornersAccent.opacity(AppDesign.Opacity.light))

            ForEach(0..<4, id: \.self) { i in
                let xs: [CGFloat] = [0.28, 0.72, 0.28, 0.72]
                let ys: [CGFloat] = [0.28, 0.28, 0.72, 0.72]
                RoundedRectangle(cornerRadius: 2)
                    .fill(SaveFarmPalette.fourCornersAccent)
                    .frame(width: 14, height: 14)
                    .position(x: size.width * xs[i], y: size.height * ys[i])
            }
        }
    }
}

private struct BeachFarmGlyph: View {
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                .fill(SaveFarmPalette.beachBg)

            Path { p in
                p.move(to: CGPoint(x: 0, y: size.height * 0.72))
                p.addQuadCurve(
                    to: CGPoint(x: size.width, y: size.height * 0.72),
                    control: CGPoint(x: size.width * 0.50, y: size.height * 0.62)
                )
                p.addLine(to: CGPoint(x: size.width, y: size.height * 0.78))
                p.addQuadCurve(
                    to: CGPoint(x: 0, y: size.height * 0.78),
                    control: CGPoint(x: size.width * 0.50, y: size.height * 0.88)
                )
                p.closeSubpath()
            }
            .fill(SaveFarmPalette.beachAccent)

            Path { p in
                p.move(to: CGPoint(x: size.width * 0.25, y: size.height * 0.78))
                p.addLine(to: CGPoint(x: size.width * 0.55, y: size.height * 0.55))
                p.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.50))
                p.addLine(to: CGPoint(x: size.width * 0.40, y: size.height * 0.78))
                p.closeSubpath()

                p.move(to: CGPoint(x: size.width * 0.55, y: size.height * 0.55))
                p.addLine(to: CGPoint(x: size.width * 0.50, y: size.height * 0.40))
                p.addLine(to: CGPoint(x: size.width * 0.65, y: size.height * 0.45))
                p.closeSubpath()
            }
            .fill(SaveFarmPalette.beachAccent.opacity(AppDesign.Opacity.secondary))
        }
    }
}

private struct MeadowlandsFarmGlyph: View {
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                .fill(SaveFarmPalette.meadowlandsBg)

            Path { p in
                p.move(to: CGPoint(x: 0, y: size.height * 0.50))
                p.addQuadCurve(
                    to: CGPoint(x: size.width, y: size.height * 0.50),
                    control: CGPoint(x: size.width * 0.50, y: size.height * 0.42)
                )
                p.addLine(to: CGPoint(x: size.width, y: size.height * 0.58))
                p.addQuadCurve(
                    to: CGPoint(x: 0, y: size.height * 0.58),
                    control: CGPoint(x: size.width * 0.50, y: size.height * 0.66)
                )
                p.closeSubpath()
            }
            .fill(SaveFarmPalette.meadowlandsAccent.opacity(AppDesign.Opacity.light))

            ForEach(0..<5, id: \.self) { i in
                let xs: [CGFloat] = [0.12, 0.30, 0.50, 0.70, 0.88]
                Path { p in
                    p.move(to: CGPoint(x: size.width * xs[i], y: size.height * 0.85))
                    p.addLine(to: CGPoint(x: size.width * xs[i], y: size.height * 0.55))
                    p.addQuadCurve(
                        to: CGPoint(x: size.width * xs[i], y: size.height * 0.85),
                        control: CGPoint(x: size.width * (xs[i] + 0.05), y: size.height * 0.70)
                    )
                    p.closeSubpath()
                }
                .fill(SaveFarmPalette.meadowlandsAccent)
                .frame(width: 4, height: size.height * 0.30)
            }

            ForEach(0..<3, id: \.self) { i in
                let xs: [CGFloat] = [0.25, 0.50, 0.72]
                let ys: [CGFloat] = [0.32, 0.22, 0.30]
                Circle()
                    .fill(SaveFarmPalette.meadowlandsAccent)
                    .frame(width: 6, height: 6)
                    .position(x: size.width * xs[i], y: size.height * ys[i])
            }
        }
    }
}

private struct ModFarmGlyph: View {
    let sfSymbol: String
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDesign.Radius.sm)
                .fill(AppDesign.Color.controlBg)
            Image(systemName: sfSymbol)
                .font(.system(size: 32))
                .foregroundStyle(AppDesign.Color.secondary)
        }
    }
}