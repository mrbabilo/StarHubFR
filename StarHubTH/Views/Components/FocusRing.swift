import SwiftUI

/// La bague de focus clavier de l'app (2026-10-17, demande de l'auteur : la
/// bague système était « laide, trop épaisse, trop vive »). Avec la
/// navigation clavier complète de macOS, chaque bouton focalisé en porte une ;
/// celle-ci suit l'arrondi du bouton, fait 2 pt, et se tient à 2 pt du bord
/// pour ne pas mordre le contenu.
///
/// ⚠️ Le retrait de la bague système et la pose de celle-ci vont **ensemble,
/// bouton par bouton** : jamais de `.focusEffectDisabled()` sur un conteneur.
/// Un bouton oublié garde ainsi la bague système, au lieu de perdre tout
/// repère de focus — la bague sert à qui navigue au clavier.
struct FocusRing: ViewModifier {
    /// L'arrondi du bouton lui-même ; la bague l'agrandit de son écart.
    var cornerRadius: CGFloat
    /// Dessinée **dans** le bouton, sans écart : pour les segments serrés
    /// dans un conteneur qui découpe (sélecteurs thème et langue de la
    /// barre), où une bague extérieure serait rognée et mordrait le voisin.
    var inset = false
    @FocusState private var isFocused: Bool
    /// Fenêtre inactive : la bague système s'efface, celle-ci aussi.
    @Environment(\.controlActiveState) private var activeState

    /// Un bouton en capsule (puces, pastilles) : un rayon assez grand pour
    /// que l'arrondi soit borné par la hauteur.
    static let capsule: CGFloat = 1_000

    private static let gap: CGFloat = 2
    private static let width: CGFloat = 2

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .focusEffectDisabled()
            .overlay {
                RoundedRectangle(cornerRadius: inset ? cornerRadius : cornerRadius + Self.gap, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.85), lineWidth: Self.width)
                    .padding(inset ? 0 : -(Self.gap + Self.width))
                    .opacity(isFocused && activeState != .inactive ? 1 : 0)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// `cornerRadius` : 6 pour un bouton bordé de taille normale, 5 en
    /// `.small`, celui de sa forme pour une rangée ou une carte.
    func focusRing(cornerRadius: CGFloat = 6, inset: Bool = false) -> some View {
        modifier(FocusRing(cornerRadius: cornerRadius, inset: inset))
    }
}
