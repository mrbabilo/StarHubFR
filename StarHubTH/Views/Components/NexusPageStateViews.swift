import SwiftUI

/// L'état de la page Nexus d'un mod, rendu en trois endroits — le badge de
/// ligne et de carte de grille, et le bandeau de fiche (A2-T6). L'état vient
/// de la reprise du dernier check (`vm.nexusPageState(for:)`) : supprimée
/// (404, terminal) ou indisponible (cachée par l'auteur, potentiellement
/// temporaire). Rien à afficher tant que la reprise n'a rien observé.
struct NexusPageBadge: View {
    let state: NexusPageState
    let L: (String) -> String

    private var tint: Color { state == .removed ? .red : .orange }
    private var glyph: String { state == .removed ? "xmark.circle.fill" : "eye.slash.fill" }
    private var hintKey: String {
        state == .removed ? L10n.Mods.nexusPageRemovedHint : L10n.Mods.nexusPageUnavailableHint
    }

    var body: some View {
        Image(systemName: glyph)
            .font(AppDesign.Font.iconXXS)
            .foregroundColor(tint)
            // Cible 18×18 : le glyphe nu rendrait `.help` muet (a11y §7).
            .frame(width: 18, height: 18)
            .contentShape(.rect)
            .help(L(hintKey))
            .accessibilityLabel(L(state == .removed
                ? L10n.Mods.nexusPageRemoved : L10n.Mods.nexusPageUnavailable))
    }
}

/// Le bandeau permanent de la fiche, jumeau de `CompatibilityBanner` : même
/// place, même vocabulaire visuel — rouge quand c'est terminé, orange quand
/// ça peut revenir.
struct NexusPageBanner: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem

    var body: some View {
        if let found = vm.nexusPageState(for: mod) {
            let removed = found.state == .removed
            let tint: Color = removed ? .red : .orange
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: removed ? "xmark.circle.fill" : "eye.slash.fill")
                        .font(.system(size: 11))
                        .foregroundColor(tint)
                    Text(localization.L(removed ? L10n.Mods.nexusPageRemoved
                                                : L10n.Mods.nexusPageUnavailable))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(tint)
                }
                // Un pack nomme le composant porteur, comme le bandeau de
                // compatibilité : le dossier s'active, l'enfant s'avise.
                if mod.isGroup, found.component.uniqueId != mod.uniqueId {
                    Text(String(format: localization.L(L10n.Mods.compatInPack),
                                found.component.name))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Text(localization.L(removed ? L10n.Mods.nexusPageRemovedHint
                                            : L10n.Mods.nexusPageUnavailableHint))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.10)))
            .padding(.top, 4)
        }
    }
}
