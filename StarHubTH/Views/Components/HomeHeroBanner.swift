import SwiftUI

/// L'en-tête de l'accueil : le bandeau Nexus pleine largeur, l'avatar Steam
/// posé à cheval sur son bord bas (disque plein, pastille feuille), puis le
/// nom du joueur et la version de l'app.
///
/// Celui de la v1.6.0, retiré par H-T3 (l'identité avait migré vers
/// `AccountHeaderCard`) et remis à la demande de l'auteur le 2026-09-24 :
/// l'accueil garde sous lui la bande d'attention et la carte de lancement.
///
/// I-T32c (2026-10-19) : tout reste, mais plus petit — le bandeau plafonné en
/// hauteur, l'avatar et le nom réduits —, pour que la bande d'attention et le
/// lancement remontent dans le premier écran. Le slogan anglais incrusté dans
/// l'image reste, par décision de l'auteur.
struct HomeHeroBanner: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    /// Diamètre du disque ; l'avatar le déborde de moitié sous le bandeau.
    private static let disc: CGFloat = 64

    /// Hauteur maximale du bandeau : à pleine largeur, l'image (3 : 1)
    /// atteignait plus de 300 pt et repoussait le lancement sous le pli.
    private static let bannerMaxHeight: CGFloat = 180

    /// Le bandeau embarqué (`assets/custom_ui`), lu une fois — même source
    /// que le héros de sauvegarde. Absent : l'avatar reste, sans bandeau.
    private static let bannerImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "nexus_banner_final",
                                        withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        VStack(spacing: AppDesign.Spacing.xs) {
            ZStack(alignment: .bottom) {
                if let banner = Self.bannerImage {
                    Image(nsImage: banner)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
                        .frame(maxHeight: Self.bannerMaxHeight)
                }
                avatarDisc
                    .offset(y: Self.disc / 2)
            }
            .padding(.bottom, Self.disc / 2)

            Text(vm.steamUsername.isEmpty
                 ? localization.L(L10n.Main.playerFallback)
                 : vm.steamUsername)
                .font(.system(size: AppDesign.Font.scaled(17), weight: .bold))
                .lineLimit(1)
            Text(String(format: localization.L(L10n.Settings.appVersion), Self.appVersion))
                .font(AppDesign.Font.rowTitle)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var avatarDisc: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: Self.disc, height: Self.disc)
                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
            if let path = vm.steamAvatarPath, let avatar = NSImage(contentsOfFile: path) {
                Image(nsImage: avatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.disc - 6, height: Self.disc - 6)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: AppDesign.Font.scaled(28)))
                    .foregroundColor(.secondary)
            }
            Image(systemName: "leaf.fill")
                .font(.system(size: AppDesign.Font.scaled(14)))
                .foregroundColor(.green)
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 18, height: 18))
                .offset(x: 21, y: 21)
        }
        .frame(width: Self.disc, height: Self.disc)
        .accessibilityHidden(true)
    }
}
