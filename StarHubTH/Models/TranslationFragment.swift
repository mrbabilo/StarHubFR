import Foundation

/// Une sélection de l'anglais, jugée avant d'être envoyée à un service de
/// traduction.
///
/// Un fragment n'est pas une valeur : il n'a ni ses marques ni sa phrase.
/// C'est pour cela qu'il se juge à part — une marque prise au milieu d'une
/// sélection reviendrait traduite ou déformée, et la proposition rendue
/// porterait cette marque abîmée jusque dans le français d'un clic.
public enum TranslationFragment {

    public enum Preparation: Equatable, Sendable {
        /// Prêt à partir, espaces de bord retirés.
        case ready(String)
        /// Rien à traduire.
        case empty
        /// La sélection emporte des marques du jeu, nommées ici pour que
        /// l'utilisateur sache autour de quoi resélectionner.
        case containsMarkers([String])
    }

    public static func prepare(_ selection: String) -> Preparation {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        // Toute marque reconnue est « dure » dans ce dépôt : le saut de ligne
        // littéral et les apostrophes appariées, eux, ne sont pas reconnus —
        // ils ne bloquent pas l'écriture et n'ont pas à bloquer ici.
        let markers = Array(Set(TranslationTokenCheck.extract(trimmed))).sorted()
        guard markers.isEmpty else { return .containsMarkers(markers) }
        return .ready(trimmed)
    }
}
