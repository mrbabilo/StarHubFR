import Foundation

/// Ce que la barre de filtres du diff peut cadrer : un état du diff, ou
/// le drapeau « À relire » posé par le lot — qui n'est pas un état mais
/// un drapeau du magasin de références, filtré par la même barre.
///
/// Dans son propre fichier : `TranslationCoverage.swift` est verrouillé par
/// le cliquet des tailles (patron `ArchivePaths`), et le type vit imbriqué
/// dans son modèle par une extension cross-fichier — le nom public reste
/// `TranslationCoverage.DiffFilter`.
extension TranslationCoverage {
    public enum DiffFilter: Equatable {
        case state(DiffRow.State)
        case reviewNeeded
    }
}
