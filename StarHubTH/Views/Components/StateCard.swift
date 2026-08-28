import SwiftUI

/// Un état vide, en panne ou jamais chargé ne reste **jamais muet** (spec
/// refonte §2, P1) : une icône, un texte, et l'action qui lève l'état.
///
/// `actionTitle` est facultatif parce qu'un état sans issue existe — « aucun
/// résultat », sans filtre à retirer, n'a rien à proposer. Il se rend alors
/// sans bouton plutôt qu'avec un bouton inerte.
struct StateCard: View {
    let icon: String
    let text: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: AppDesign.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: AppDesignCore.Icon.md))
                .foregroundStyle(.tertiary)
            Text(text).font(AppDesign.Font.body).foregroundStyle(.secondary)
            Spacer(minLength: AppDesign.Spacing.sm)
            if let actionTitle {
                Button(actionTitle, action: action).buttonStyle(.link)
            }
        }
        .padding(AppDesign.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary,
                    in: RoundedRectangle(cornerRadius: AppDesign.Radius.section))
        .overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.section)
            .stroke(Color.primary.opacity(AppDesign.Opacity.light), lineWidth: 1))
    }
}
