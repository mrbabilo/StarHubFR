import SwiftUI

/// Le bandeau d'une fiche : l'image du sujet, son nom et son sous-titre
/// par-dessus. Le titre nu sur fond clair ne disait pas de quoi on parlait
/// tant que le contenu n'était pas chargé.
///
/// Le texte se lit sur n'importe quelle image parce que le dégradé le garantit
/// (spec refonte §2, P8) — c'est le seul contraste qu'on maîtrise ici.
///
/// La croix de fermeture mesure `Icon.sm`, sous la cible de 18×18 pt que la
/// spec §7 exige, et sans `help()` : l'agrandir déplacerait le glyphe sous le
/// padding existant, et la libeller demanderait une chaîne nouvelle — deux
/// choses interdites en phase 0. À reprendre avec l'accessibilité (I-T3).
struct HeroHeader: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    let onClose: () -> Void

    var body: some View {
        Rectangle().fill(.quaternary)
            .frame(height: AppDesignCore.Metrics.heroHeight)
            .overlay {
                if let imageURL {
                    CachedAsyncImage(url: imageURL)
                }
            }
            .clipped()
            .overlay {
                // Le texte se lit sur n'importe quelle image : le dégradé est
                // la seule garantie de contraste qu'on maîtrise.
                LinearGradient(colors: [.clear, .black.opacity(0.65)],
                               startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppDesign.Font.viewTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(AppDesign.Font.caption)
                        .foregroundStyle(.white.opacity(AppDesign.Opacity.secondary))
                }
                .padding(AppDesign.Spacing.lg)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: AppDesignCore.Icon.sm))
                        .foregroundStyle(.white.opacity(AppDesign.Opacity.secondary))
                }
                .buttonStyle(.plain)
                .padding(AppDesign.Spacing.sm)
            }
    }
}
