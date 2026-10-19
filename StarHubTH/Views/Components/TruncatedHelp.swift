import SwiftUI

extension View {
    /// Un texte borné à `lines` lignes, qui rend son texte entier en
    /// infobulle quand la place manque (I-T32b : aucun texte principal
    /// tronqué sans infobulle).
    ///
    /// Les trois réglages vont ensemble : un site qui en oubliait un tronquait
    /// sans aide, ou posait une infobulle sur un texte qui ne se coupe jamais.
    /// `mode` garde le choix de chaque site — `.tail` est le défaut de
    /// SwiftUI ; `.middle` pour un nom ou un chemin dont la fin distingue.
    func truncatedHelp(_ text: String, lines: Int = 1,
                       mode: Text.TruncationMode = .tail) -> some View {
        lineLimit(lines).truncationMode(mode).help(text)
    }
}
