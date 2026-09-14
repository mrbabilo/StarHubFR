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
            .font(AppDesign.Font.iconXS)
            .foregroundColor(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(AppDesign.Opacity.medium)))
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

/// A2-T7 — le bandeau d'un mod que SMAPI refuse de charger parce qu'il est
/// **malveillant**.
///
/// En rouge et au-dessus du reste : c'est la seule chose de cette fiche qui
/// parle de code hostile. Le message de SMAPI est repris tel quel — il dit quoi
/// faire, et le résumer en perdrait la consigne.
///
/// ⚠️ **Aucun bouton de suppression.** L'`UniqueID` est déclaratif : un mod peut
/// usurper celui d'un autre. On avertit, l'utilisateur agit.
struct MaliciousModBanner: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem

    /// Le composant porteur : sur un pack, c'est l'enfant qui est signalé, pas
    /// le dossier — même règle que le bandeau de compatibilité.
    private var hit: (name: String, entry: SmapiBlacklist.Entry)? {
        if let entry = vm.maliciousMods[mod.uniqueId] { return (mod.name, entry) }
        for child in mod.children ?? [] {
            if let entry = vm.maliciousMods[child.uniqueId] { return (child.name, entry) }
        }
        return nil
    }

    var body: some View {
        if let hit {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                    Text(localization.L(L10n.Mods.maliciousTitle))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                }
                if mod.isGroup, hit.name != mod.name {
                    Text(String(format: localization.L(L10n.Mods.compatInPack), hit.name))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Text(localization.L(L10n.Mods.maliciousAction))
                    .font(.system(size: 11, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                // Le message de SMAPI, en anglais dans la source : il est repris
                // mot pour mot plutôt que traduit approximativement.
                if !hit.entry.message.isEmpty {
                    Text(hit.entry.message)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.12)))
            .padding(.top, 4)
        }
    }
}
