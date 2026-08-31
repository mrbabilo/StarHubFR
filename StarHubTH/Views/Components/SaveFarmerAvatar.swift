import SwiftUI

struct SaveFarmerAvatar: View, Equatable {
    // Le chapeau est dimensionné à `size * 0.6` de haut, ancré en bas — toute modification de `size` reste dans le cadre.
    let hairStyle: Int
    let hairColor: Int
    let skinIndex: Int
    let size: CGFloat

    init(hairStyle: Int, hairColor: Int, skinIndex: Int, size: CGFloat = 40) {
        self.hairStyle = hairStyle
        self.hairColor = hairColor
        self.skinIndex = skinIndex
        self.size = size
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(SaveFarmerPalette.skinColor(for: skinIndex))
                .frame(width: size, height: size)

            let shape = SaveFarmerPalette.hatShape(for: hairStyle)
            if shape != .bald {
                SaveFarmerHatShape(style: shape)
                    .fill(SaveFarmerPalette.hairColor(for: hairColor))
                    .frame(width: size, height: size * 0.6)
            }
        }
        .frame(width: size, height: size * 0.9, alignment: .bottom)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hairStyle == rhs.hairStyle
            && lhs.hairColor == rhs.hairColor
            && lhs.skinIndex == rhs.skinIndex
            && lhs.size == rhs.size
    }
}

private struct SaveFarmerHatShape: Shape {
    let style: SaveFarmerPalette.HatShape

    func path(in rect: CGRect) -> Path {
        switch style {
        case .bald:
            return Path()
        case .short:
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addArc(center: CGPoint(x: rect.midX, y: rect.maxY),
                     radius: rect.width / 2,
                     startAngle: .radians(.pi),
                     endAngle: .radians(0),
                     clockwise: false)
            p.closeSubpath()
            return p
        case .long:
            let overflow = rect.width * 0.1
            let topY = rect.maxY - rect.height * 0.7
            var p = Path()
            p.move(to: CGPoint(x: rect.minX - overflow, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.2, y: topY))
            p.addLine(to: CGPoint(x: rect.midX, y: topY - rect.height * 0.1))
            p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.2, y: topY))
            p.addLine(to: CGPoint(x: rect.maxX + overflow, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }
}