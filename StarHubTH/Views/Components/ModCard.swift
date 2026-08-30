import AppKit
import SwiftUI

/// La carte d'un mod : vignette **pleine largeur en 16/9**, pastille d'état
/// posée dessus, puis titre, auteur, et une seule ligne de métadonnées.
///
/// Toutes les places sont réservées (spec refonte §2, P4) — vignette, titre à
/// deux lignes, ligne de méta : sur la sélection française, où beaucoup de
/// traductions n'ont pas d'image, une carte plus courte que sa voisine
/// décalerait toute la rangée.
///
/// Paramétré par des valeurs et non par un type de domaine : le lot Mods
/// l'alimentera depuis un `ModItem`, qui n'a ni endossements ni catégorie
/// Nexus servis.
/// Un attribut porté par une carte : le glyph, sa teinte s'il en demande une,
/// et ce que dit son infobulle.
struct CardAttribute: Identifiable {
    let id: String
    let systemImage: String
    var tint: Color?
    let help: String
}

struct ModCard: View {
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
    /// Le libellé de la pastille posée sur la vignette, ou `nil` quand il n'y
    /// a rien à y poser.
    let installedLabel: String?
    /// La teinte et le glyph de cette pastille. Découvrir garde les valeurs
    /// par défaut — vert plein, coche : elle y dit « déjà installé ». La
    /// grille des mods installés s'en sert pour dire l'**état** (actif / en
    /// pause), où le vert seul mentirait sur la moitié des cartes.
    var badgeTint: Color = .green
    var badgeSystemImage: String = "checkmark.circle.fill"
    let category: NexusCategory?
    /// Une pastille neutre supplémentaire (« FR »), ou `nil`.
    let neutralBadge: String?
    let endorsements: Int?
    /// Ce qui tient la place d'une vignette absente. Découvrir garde le
    /// rectangle gris (`false`) — sa vitrine sert des captures Nexus et
    /// l'absence y est l'exception. La grille des mods installés l'allume :
    /// 148 de ses 887 dossiers n'ont aucune image à servir, et une page
    /// entière de rectangles gris se lisait comme un écran qui n'a pas fini
    /// de charger.
    var usesDefaultArtwork: Bool = false
    /// Les attributs du mod — anomalie, note, config gardée par le profil.
    /// La grille des mods installés les montre comme la liste ; Découvrir
    /// n'en a aucun (un mod de la vitrine n'est pas encore chez soi).
    ///
    /// Ils ne portent qu'une infobulle : la carte entière est déjà un bouton,
    /// et un bouton dans un bouton ne se clique pas sur macOS. Le détail se
    /// lit dans la fiche, qu'ouvre le clic.
    var attributes: [CardAttribute] = []
    /// Passé tel quel à `CategoryBadge`, qui résout le nom localisé.
    let L: (String) -> String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                thumbnail
                VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                    Text(title)
                        .font(AppDesign.Font.body(.semibold))
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(AppDesign.Font.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    metaRow
                }
                .padding(.horizontal, AppDesign.Spacing.md)
                .padding(.top, 10)
                .padding(.bottom, AppDesign.Spacing.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.section))
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.section)
                    .stroke(Color.primary.opacity(AppDesign.Opacity.light), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Le rectangle gris couvre l'absence d'image, l'attente et l'échec de
    /// chargement — trois cas qui, sans lui, donneraient trois hauteurs.
    private var thumbnail: some View {
        Rectangle().fill(.quaternary)
            .aspectRatio(AppDesign.Metrics.thumbRatio, contentMode: .fit)
            // L'illustration de l'app (celle de l'écran de lancement), sous
            // la vignette et **voilée** : elle occupe la place, elle ne se
            // fait pas passer pour la capture du mod. Elle n'est dessinée
            // que faute de mieux, et seulement là où l'écran la demande.
            .overlay {
                if usesDefaultArtwork, thumbnailURL == nil, let art = Self.defaultArtwork {
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                        .opacity(AppDesign.Opacity.strong)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                // `CachedAsyncImage` garde les images en mémoire : dérouler
                // la vitrine redemanderait sinon les mêmes vignettes au
                // réseau à chaque passage.
                if let thumbnailURL {
                    CachedAsyncImage(url: thumbnailURL)
                }
            }
            .clipped()
            // Sur l'image, pas en bas de pile : c'est ce qu'on cherche en
            // balayant une grille.
            .overlay(alignment: .topTrailing) {
                if let installedLabel {
                    // Pastille **pleine**, pas translucide : posée sur un
                    // matériau, elle se noyait dans les vignettes claires. Du
                    // blanc sur vert tient sur n'importe quelle image, et
                    // l'ombre la décolle du fond.
                    Label(installedLabel, systemImage: badgeSystemImage)
                        .font(AppDesign.Font.caption(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppDesign.Spacing.sm)
                        .padding(.vertical, AppDesign.Spacing.xs)
                        .background(badgeTint, in: Capsule())
                        .shadow(color: .black.opacity(AppDesign.Opacity.strong),
                                radius: AppDesign.Shadow.badge.radius,
                                y: AppDesign.Shadow.badge.y)
                        .padding(AppDesign.Spacing.sm)
                }
            }
    }

    /// L'illustration de l'app, chargée une fois pour toutes les cartes —
    /// c'est la même image que l'écran de lancement (`LaunchSplashWindow`),
    /// déjà copiée dans les ressources du bundle par `build_app.py`.
    private static let defaultArtwork: NSImage? = {
        guard let url = Bundle.main.url(forResource: "nexus_cover_final", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    /// Une seule ligne : la catégorie à gauche, les endossements à droite.
    /// Sa hauteur est réservée — sans catégorie servie, une carte plus courte
    /// décalerait ses voisines.
    private var metaRow: some View {
        HStack(spacing: AppDesign.Spacing.xs + 2) {
            if let category {
                CategoryBadge(category: category, L: L)
            }
            if let neutralBadge {
                NeutralBadge(label: neutralBadge)
            }
            ForEach(attributes) { attribute in
                Image(systemName: attribute.systemImage)
                    .font(AppDesign.Font.iconXS)
                    .foregroundStyle(attribute.tint ?? .secondary)
                    // La cible qu'exige une infobulle vivante sur macOS.
                    .frame(width: 18, height: 18)
                    .contentShape(.rect)
                    .help(attribute.help)
                    .accessibilityLabel(attribute.help)
            }
            Spacer(minLength: 0)
            if let endorsements {
                Label("\(endorsements)", systemImage: "hand.thumbsup")
                    .font(AppDesign.Font.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: AppDesign.Metrics.metaRowHeight)
        .padding(.top, 2)
    }
}
