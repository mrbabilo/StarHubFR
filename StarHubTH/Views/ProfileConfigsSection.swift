import SwiftUI

/// R4 (audit UX 2026-10-16) — les `config.json` qu'un profil retient, dans la
/// feuille du profil : la liste entière (la rangée n'en nommait que cinq
/// orphelins) et, par mod, la comparaison avec un autre profil.
///
/// La comparaison oppose toujours le profil **actif** à un autre
/// (`profileConfigDiffs`) : depuis un profil inactif, un seul bouton ; depuis
/// l'actif, le menu des autres. Comme dans la fiche, elle ne s'offre que pour
/// un mod géré par profil (`isProfileConfigManaged`).
struct ProfileConfigsSection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let profile: ModProfile
    let overview: ProfileConfigOverview
    /// Le mod et le profil à opposer à l'actif. Confié à la feuille : la
    /// comparaison remplace son contenu.
    let onCompare: (ModItem, ModProfile) -> Void

    var body: some View {
        if overview.total > 0 {
            let installed = Dictionary(viewModel.mods.flattenedMods.map { ($0.folderName, $0) },
                                       uniquingKeysWith: { first, _ in first })
            let others = viewModel.modProfiles.filter { $0.id != viewModel.activeProfileId }
            VStack(alignment: .leading, spacing: 0) {
                Text(String(format: localization.L(L10n.Profiles.configStored), Int64(overview.total)))
                    .font(AppDesign.Font.caption)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                ForEach(overview.rows) { row in
                    Divider().padding(.leading, 20)
                    configRow(row, mod: installed[row.folderName], others: others)
                }
            }
        }
    }

    private func configRow(_ row: ProfileConfigOverview.Row, mod: ModItem?, others: [ModProfile]) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(AppDesign.Font.body)
                if !row.isInstalled {
                    // Glyphe et couleur (P6) : l'orange seul ne dit pas « disparu ».
                    Label(localization.L(L10n.Profiles.configOrphanRow), systemImage: AppDesign.Status.warning.symbol)
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(AppDesign.Color.warning)
                }
            }
            Spacer()
            if let mod {
                compareControl(mod, others: others)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func compareControl(_ mod: ModItem, others: [ModProfile]) -> some View {
        let managed = viewModel.isProfileConfigManaged(mod)
        Group {
            if profile.id != viewModel.activeProfileId {
                Button(localization.L(L10n.Profiles.configCompareActive)) { onCompare(mod, profile) }.focusRing(cornerRadius: 5)
            } else {
                Menu(localization.L(L10n.Mods.profileConfigCompare)) {
                    ForEach(others) { other in
                        Button(other.name) { onCompare(mod, other) }
                    }
                }
                .fixedSize().focusRing(cornerRadius: 5)
                .disabled(others.isEmpty)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!managed)
        .help(managed ? "" : localization.L(L10n.Profiles.configCompareUnmanaged))
        .pointingHandCursor()
    }
}
