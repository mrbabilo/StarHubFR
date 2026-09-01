import SwiftUI

/// Vignette de ferme du hero de sauvegarde : les 8 fermes vanilla en
/// illustrations embarquées (`farm_glyph_0…7.png` dans les resources,
/// ordre du wiki = `whichFarm`), remplissage couvrant et coins arrondis.
/// Les fermes de mods (`whichFarm` hors 0-7) retombent sur un SF Symbol
/// proportionnel à la vignette.
///
/// Ce composant remplace les glyphes vectoriels dessinés à la main (H-T5b) :
/// jugés illisibles à 80×56 à l'écran, ils ont cédé la place aux vignettes
/// illustrées — les formes dessinées exigeaient des détails plus petits que
/// ce que l'œil y résout.
struct SaveFarmGlyph: View, Equatable {
    let whichFarm: Int
    let size: CGSize

    init(whichFarm: Int, size: CGSize = CGSize(width: 80, height: 56)) {
        self.whichFarm = whichFarm
        self.size = size
    }

    /// Les vues s'évaluent sur le fil principal : ce cache simple évite de
    /// relire le PNG à chaque apparition de fiche, sans verrou.
    private static var imageCache: [Int: NSImage] = [:]

    private func farmImage() -> NSImage? {
        guard (0...7).contains(whichFarm) else { return nil }
        if let cached = Self.imageCache[whichFarm] { return cached }
        guard let url = Bundle.main.url(forResource: "farm_glyph_\(whichFarm)",
                                        withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        Self.imageCache[whichFarm] = img
        return img
    }

    var body: some View {
        Group {
            if let img = farmImage() {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(AppDesign.Color.controlBg)
                    Image(systemName: SaveGameInfo.farmIcon(for: whichFarm))
                        .font(.system(size: min(size.width, size.height) * 0.40))
                        .foregroundStyle(AppDesign.Color.secondary)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.sm))
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.whichFarm == rhs.whichFarm && lhs.size == rhs.size
    }
}
