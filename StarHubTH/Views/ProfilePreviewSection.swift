import SwiftUI

/// P5-1 (audit UX 2026-10-16) — ce qu'activer le profil ferait, dans la
/// feuille du profil : la seule façon de le voir était de l'activer.
///
/// Les chiffres sont des **dossiers** de `Mods/`, ceux que le disque
/// renommerait, et pas les identifiants de la colonne « Mods » de la rangée :
/// un pack compte pour un dossier. Les listes sont repliées, une mise en
/// pause en compte 218 sur le parc de l'auteur.
///
/// Rien ici n'active le profil : le bouton « Activer » de la rangée garde ses
/// alertes (empreintes, conflits), qu'une feuille ouverte pourrait masquer.
struct ProfilePreviewSection: View {
    @ObservedObject var localization: LocalizationStore
    let preview: ProfileApplyPreview
    /// Un scan en vol rendrait l'aperçu faux sans le dire.
    let isScanning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
            if isScanning {
                note(localization.L(L10n.ProfilePreview.scanning))
            } else if preview.isEmpty {
                note(localization.L(L10n.ProfilePreview.nothing))
            } else {
                note(localization.L(L10n.ProfilePreview.readOnly))
                moveGroup(localization.plural(L10n.ProfilePreview.toEnable, preview.toEnable.count),
                          preview.toEnable)
                moveGroup(localization.plural(L10n.ProfilePreview.toDisable, preview.toDisable.count),
                          preview.toDisable)
                if !preview.conflicts.isEmpty {
                    conflicts
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(AppDesign.Font.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func moveGroup(_ title: String, _ moves: [ProfileApplyPlan.Move]) -> some View {
        if !moves.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(moves, id: \.source) { move in
                        Text(move.modName)
                            .font(AppDesign.Font.footnote)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(title)
                    .font(AppDesign.Font.body)
            }
        }
    }

    /// Les paires que la garde de l'activation opposera : glyphe et couleur,
    /// jamais la couleur seule (P6).
    private var conflicts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(localization.plural(L10n.ProfilePreview.conflicts, preview.conflicts.count),
                  systemImage: AppDesign.Status.warning.symbol)
                .font(AppDesign.Font.body)
                .foregroundColor(AppDesign.Color.warning)
            ForEach(preview.conflicts, id: \.self) { pair in
                Text("\(pair.first) ↔ \(pair.second)")
                    .font(AppDesign.Font.footnote)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
