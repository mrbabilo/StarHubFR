import SwiftUI

/// Ce que deux profils retiennent du `config.json` d'un mod, clé à clé —
/// l'écran qui rend la divergence *lisible* (spec §7).
///
/// **Lecture seule**, délibérément : un bouton « copier cette valeur de A
/// vers B » ouvrirait un second chemin d'écriture dans les configs ; la spec
/// exige le premier éprouvé avant d'instruire le second. Le patron vient de
/// `TranslationRecoveryDiffView` ; le code n'est pas repris — la
/// comparaison de traduction travaille sur des fichiers plats, celle-ci
/// sur des arbres à 8 niveaux.
struct ProfileConfigCompareView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem
    let other: ModProfile
    @Binding var isPresented: Bool
    /// R4 — dans la feuille d'un profil, la comparaison **remplace** son
    /// contenu (pas de feuille sur feuille) : pas de taille propre, et le
    /// bouton du pied ramène à la liste au lieu de fermer.
    var embedded = false

    /// Rempli à l'apparition, jamais au rendu : chaque appel ouvre et
    /// décode les magasins des deux profils.
    @State private var diffs: [ConfigKeyDiff] = []
    @State private var unparseable = false
    @State private var missing = false

    private var activeName: String {
        vm.modProfiles.first(where: { $0.id == vm.activeProfileId })?.name ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: localization.L(L10n.Mods.profileConfigDiffTitle),
                            mod.name, activeName, other.name))
                    .font(AppDesign.Font.headline(.semibold))
                Text(localization.L(L10n.Mods.profileConfigDiffNote))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Divider()

            if missing {
                centered(localization.L(L10n.Mods.profileConfigDiffMissing))
            } else if unparseable {
                centered(localization.L(L10n.Mods.profileConfigDiffUnparseable))
            } else if diffs.isEmpty {
                centered(localization.L(L10n.Mods.profileConfigDiffNone))
            } else {
                ConfigDiffList(localization: localization, diffs: diffs, nameA: activeName, nameB: other.name)
            }

            Divider()

            HStack {
                Spacer()
                Button(embedded ? "‹ " + localization.L(L10n.Main.navBack) : localization.L(L10n.Main.ok)) {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: embedded ? nil : 720, height: embedded ? nil : 540)
        .onAppear {
            // Rien mémorisé d'un côté : ce n'est ni une erreur ni un diff —
            // l'écran le dit, il ne l'invente pas.
            guard let active = vm.modProfiles.first(where: { $0.id == vm.activeProfileId }),
                  vm.profileConfigText(mod: mod, profile: active) != nil,
                  vm.profileConfigText(mod: mod, profile: other) != nil else {
                missing = true
                return
            }
            if let result = vm.profileConfigDiffs(mod: mod, other: other) {
                diffs = result
            } else {
                unparseable = true
            }
        }
    }

    private func centered(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(AppDesign.Font.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
