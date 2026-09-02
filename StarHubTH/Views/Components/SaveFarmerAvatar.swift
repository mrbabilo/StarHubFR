import SwiftUI

/// Avatar du fermier du hero : vignette circulaire sur le visage du
/// personnage (`farmer_face_male/female.png`, embarqués dans les
/// resources), choisie selon le sexe lu dans la sauvegarde.
///
/// ⚠️ **Ce que l'avatar ne montre pas.** L'illustration est fixe par sexe :
/// la coiffure (`<hair>`), sa couleur (`<hairstyleColor>`) et la peau
/// (`<skin>`) sont lues dans la save mais **ne sont rendues que par le repli
/// vectoriel**, quand l'illustration manque. Les teinter sur l'illustration
/// a été mesuré comme impraticable : ce sont des crops de l'affiche du jeu,
/// où le brun des cheveux est exactement celui du bois de la ferme derrière
/// le personnage — aucun masque colorimétrique ne les sépare. Rendre la vraie
/// tête demanderait de la recomposer, pas de la teinter.
/// Qui veut un portrait fidèle pose une **icône personnalisée** sur la
/// sauvegarde : `SaveHeroBand` la préfère alors à cette illustration.
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

    /// Cache des illustrations, sous verrou dédié — la convention du dépôt
    /// pour tout état statique mutable (CLAUDE.md §Concurrence). La valeur est
    /// optionnelle pour mémoïser aussi les **échecs** : sans cela, une resource
    /// absente relit le disque à chaque évaluation de `body`.
    private static var faceCache: [Bool: NSImage?] = [:]
    private static let faceCacheLock = NSLock()

    /// Cadrage de l'illustration, mesuré sur les **deux** visages (revue
    /// design du 2026-09-02, découpes rendues hors app) : à ce zoom et cette
    /// remontée, les yeux tombent au tiers haut, la coiffure reste entière et
    /// l'épaule n'entre qu'à peine. Sans eux, le cadrage plein pot laissait la
    /// moitié du disque au décor de la ferme et la tête trop basse.
    /// `faceRise` est exprimée pour un disque de 76 pt et suit la taille.
    private static let faceZoom: CGFloat = 1.34
    private static let faceRise: CGFloat = 6
    private static let faceRiseReferenceSize: CGFloat = 76

    private static func faceImage(isFemale: Bool) -> NSImage? {
        faceCacheLock.lock()
        let cached = faceCache[isFemale]
        faceCacheLock.unlock()
        if let cached = cached { return cached }

        let name = isFemale ? "farmer_face_female" : "farmer_face_male"
        let loaded = Bundle.main.url(forResource: name, withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
        faceCacheLock.lock()
        faceCache[isFemale] = loaded
        faceCacheLock.unlock()
        return loaded
    }

    var body: some View {
        Group {
            if let img = Self.faceImage(isFemale: isFemale) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(Self.faceZoom)
                    .offset(y: -Self.faceRise * size / Self.faceRiseReferenceSize)
            } else {
                // Repli vectoriel : tête de la couleur de peau, chevelure
                // de la couleur lue dans la save, posée sur le **crâne**.
                ZStack(alignment: .top) {
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
        .overlay(Circle().stroke(Color.white.opacity(0.92), lineWidth: 2))
        .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isFemale == rhs.isFemale
            && lhs.hairStyle == rhs.hairStyle
            && lhs.hairColor == rhs.hairColor
            && lhs.skinIndex == rhs.skinIndex
            && lhs.size == rhs.size
    }
}

/// Chevelure du repli vectoriel. Les deux formes sont ancrées au **haut** du
/// rectangle : ancrées en bas (`rect.maxY`), elles couvraient la moitié
/// inférieure du visage — des cheveux sur le menton.
private struct SaveFarmerHatShape: Shape {
    let style: SaveFarmerPalette.HatShape

    func path(in rect: CGRect) -> Path {
        switch style {
        case .bald:
            return Path()
        case .short:
            // Demi-disque posé sur le crâne, diamètre horizontal en bas.
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addArc(center: CGPoint(x: rect.midX, y: rect.maxY),
                     radius: rect.width / 2,
                     startAngle: .radians(.pi),
                     endAngle: .radians(2 * .pi),
                     clockwise: false)
            p.closeSubpath()
            return p
        case .long:
            // Coiffe qui déborde sur les côtés et redescend en mèches.
            let overflow = rect.width * 0.1
            let crownY = rect.minY + rect.height * 0.1
            var p = Path()
            p.move(to: CGPoint(x: rect.minX - overflow, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.15, y: crownY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.15, y: crownY))
            p.addLine(to: CGPoint(x: rect.maxX + overflow, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }
}
