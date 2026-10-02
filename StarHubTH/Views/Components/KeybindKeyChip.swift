import SwiftUI

/// Une combinaison de touches dessinée comme un capuchon de clavier : ce
/// qui doit sauter aux yeux dans une collision, c'est la touche. Fond de
/// contrôle, liseré, ombre de carte (jetons existants, I-T18).
struct KeybindKeyChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppDesign.Font.monoFootnote.weight(.semibold))
            .lineLimit(1).truncationMode(.middle)
            .padding(.horizontal, AppDesign.Spacing.sm)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: AppDesignCore.Radius.sm)
                .fill(AppDesign.Color.controlBg)
                .shadow(color: .black.opacity(AppDesignCore.Shadow.card.opacity),
                        radius: 1, y: 1))
            .overlay(RoundedRectangle(cornerRadius: AppDesignCore.Radius.sm)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.75))
    }
}
