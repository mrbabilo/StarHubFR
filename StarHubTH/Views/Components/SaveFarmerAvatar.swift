import SwiftUI

/// Avatar du fermier du hero : vignette circulaire sur le visage du
/// personnage (`farmer_face_male/female.png`, embarqués dans les
/// resources), choisie selon le sexe lu dans la sauvegarde. Le dessin
/// vectoriel — tête recomposée depuis coiffure/couleur/peau — reste en
/// repli si l'illustration vient à manquer.
struct SaveFarmerAvatar: View, Equatable {
    let isFemale: Bool
    let hairStyle: Int
    let hairColor: Color
    let skinIndex: Int
    let size: CGFloat

    init(isFemale: Bool, hairStyle: Int, hairColor: Color,
         skinIndex: Int, size: CGFloat = 44) {
        self.isFemale = isFemale
        self.hairStyle = hairStyle
        self.hairColor = hairColor
        self.skinIndex = skinIndex
        self.size = size
    }

    /// Les vues s'évaluent sur le fil principal : ce cache simple évite de
    /// relire le PNG à chaque apparition de fiche, sans verrou.
    private static var faceCache: [Bool: NSImage] = [:]

    private static func faceImage(isFemale: Bool) -> NSImage? {
        if let cached = faceCache[isFemale] { return cached }
        guard let url = Bundle.main.url(forResource: isFemale ? "farmer_face_female"
                                                              : "farmer_face_male",
                                        withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        faceCache[isFemale] = img
        return img
    }

    var body: some View {
        Group {
            if let img = Self.faceImage(isFemale: isFemale) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Repli vectoriel : tête de la couleur de peau, chevelure
                // de la couleur lue dans la save.
                ZStack(alignment: .bottom) {
                    Circle()
                        .fill(SaveFarmerPalette.skinColor(for: skinIndex))
                    let shape = SaveFarmerPalette.hatShape(for: hairStyle)
                    if shape != .bald {
                        SaveFarmerHatShape(style: shape)
                            .fill(hairColor)
                            .frame(width: size, height: size * 0.6)
                    }
                }
            }
        }
        // Le liseré et l'ombre détachent l'avatar de l'illustration du
        // bandeau, quelle que soit la zone qu'il recouvre.
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isFemale == rhs.isFemale
            && lhs.hairStyle == rhs.hairStyle
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
