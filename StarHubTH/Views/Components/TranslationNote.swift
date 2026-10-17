import SwiftUI

/// Une ligne de constat de la section Traduction de la fiche : glyphe et
/// texte, et, s'il y a un endroit où agir, son lien (N-11). Sortie de
/// `ModDetailView`, verrouillé par le cliquet de taille.
struct TranslationNote: View {
    let text: String
    let icon: String
    let color: Color
    var link: String?
    var action: () -> Void = {}

    init(_ text: String, icon: String, color: Color, link: String? = nil, action: @escaping () -> Void = {}) {
        self.text = text
        self.icon = icon
        self.color = color
        self.link = link
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(AppDesign.Font.iconXS)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(color == .secondary ? .secondary : color)
                    .fixedSize(horizontal: false, vertical: true)
                if let link {
                    Button(link, action: action)
                        .buttonStyle(.hoverLink)
                        .font(AppDesign.Font.footnote)
                }
            }
        }
    }
}
