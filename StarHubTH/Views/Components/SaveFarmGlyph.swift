import SwiftUI

/// Vignette de ferme du hero de sauvegarde : les 8 fermes vanilla en
/// illustrations embarquées (`farm_glyph_0…7.png` dans les resources,
/// ordre du wiki = `whichFarm`), remplissage couvrant et coins arrondis.
/// Les fermes de mods (`whichFarm` hors 0-7, dont la sentinelle `-1` posée
/// par `SaveFarmType`) retombent sur un SF Symbol proportionnel.
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

    /// Cache des illustrations, sous verrou dédié — la convention du dépôt
    /// pour tout état statique mutable (CLAUDE.md §Concurrence : un `Dictionary`
    /// statique sans verrou a déjà coûté un `EXC_BAD_ACCESS` sur `manifestCache`).
    /// La valeur est optionnelle pour mémoïser aussi les **échecs** : sans cela,
    /// une resource absente relit le disque à chaque évaluation de `body`.
    private static var imageCache: [Int: NSImage?] = [:]
    private static let imageCacheLock = NSLock()

    private static func farmImage(_ whichFarm: Int) -> NSImage? {
        guard (0...7).contains(whichFarm) else { return nil }
        imageCacheLock.lock()
        let cached = imageCache[whichFarm]
        imageCacheLock.unlock()
        if let cached = cached { return cached }

        let loaded = Bundle.main.url(forResource: "farm_glyph_\(whichFarm)", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
        imageCacheLock.lock()
        imageCache[whichFarm] = loaded
        imageCacheLock.unlock()
        return loaded
    }

    var body: some View {
        Group {
            if let img = Self.farmImage(whichFarm) {
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
