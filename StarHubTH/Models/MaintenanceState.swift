import Foundation

/// Résultat d'une action de quarantaine : le texte affiché, et s'il s'agit
/// d'une erreur (rendu en rouge, pas en vert de succès).
///
/// Vivait imbriqué dans le ViewModel ; déménage en Core avec
/// `MaintenanceStore`, qui le porte. Personne ne le nommait par son chemin
/// complet — les vues utilisent l'inférence — donc le déplacement ne touche
/// aucun appelant.
public struct QuarantineMessage: Equatable {
    public let text: String
    public let isError: Bool

    public init(text: String, isError: Bool) {
        self.text = text
        self.isError = isError
    }
}
