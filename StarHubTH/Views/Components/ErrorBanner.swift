import SwiftUI

/// Une panne se voit (spec refonte §2, P7) : bandeau teinté portant l'action
/// qui la lève, pas une ligne de texte grise qu'on lit comme une légende.
///
/// Le composant ignore le type d'erreur du domaine : c'est l'appelant qui
/// choisit le message et ce que fait le bouton.
struct ErrorBanner: View {
    let text: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: AppDesign.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.orange)
            Text(text).font(AppDesign.Font.caption)
            Spacer(minLength: AppDesign.Spacing.sm)
            Button(actionTitle, action: action).buttonStyle(.link)
        }
        .padding(.horizontal, AppDesign.Spacing.md)
        .padding(.vertical, AppDesign.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(AppDesign.Opacity.light),
                    in: RoundedRectangle(cornerRadius: AppDesign.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.md)
            .stroke(Color.orange.opacity(AppDesign.Opacity.medium * 2), lineWidth: 1))
    }
}
