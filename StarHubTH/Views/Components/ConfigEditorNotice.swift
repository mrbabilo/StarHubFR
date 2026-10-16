import SwiftUI

/// Un avis de l'éditeur de config (jeu lancé, schéma illisible) : les deux
/// bandeaux étaient recopiés à l'identique dans `ModConfigEditorView`.
struct ConfigEditorNotice: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.orange)
            Text(text)
                .font(AppDesign.Font.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
    }
}
