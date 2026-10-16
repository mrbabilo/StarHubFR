import SwiftUI

/// R7 (audit UX 2026-10-16) — le bouton qui ouvre les Réglages sur une
/// section. Écrit pour Nexus ; les messages DeepL et IA locale (N-11) le
/// reprendront avec leur section.
struct SettingsLinkButton: View {
    let section: SettingsSection
    let title: String
    let navigation: NavigationStore

    var body: some View {
        Button(title) { navigation.openSettings(section) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointingHandCursor()
    }
}

/// R7 — la clé API Nexus manque : un seul remède, quel que soit l'écran.
/// Avant, la même condition menait à la page web (Mises à jour), aux
/// Réglages (Découvrir) ou nulle part (Traductions FR, fiche).
///
/// Le message reste celui de l'écran : il dit ce que la clé y apporterait
/// (« la vérification marche sans clé » ne doit pas se lire comme un
/// barrage). Seul le geste est commun : les Réglages d'abord, la page où
/// créer une clé en second.
///
/// Pas pour le Premium : là, le bouton reste visible, désactivé, avec son
/// infobulle et le bouton Nexus à côté (`L10n.Mods.premiumOnlyHint`).
struct NexusAccessNote: View {
    let message: String
    let navigation: NavigationStore
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        HStack(alignment: .top, spacing: AppDesign.Spacing.sm) {
            Image(systemName: "key.fill")
                .foregroundColor(.secondary)
                .font(AppDesign.Font.caption)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                Text(message)
                    .font(AppDesign.Font.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Repliable : à 821 pt, la fiche n'a pas la largeur des deux.
                WrapHStack(spacing: AppDesign.Spacing.sm, lineSpacing: AppDesign.Spacing.xs) {
                    SettingsLinkButton(section: .nexus,
                                       title: localization.L(L10n.Mods.nexusOpenSettings),
                                       navigation: navigation)
                    Button {
                        NSWorkspace.shared.open(NexusRequestBuilder.apiKeyPageURL)
                    } label: {
                        Label(localization.L(L10n.Updates.nexusGetKey), systemImage: "arrow.up.right")
                            .font(AppDesign.Font.caption)
                    }
                    .buttonStyle(.hoverLink)
                }
            }
        }
    }
}
