import Foundation

/// Une frontière d'I/O — le sélecteur d'images du système.
///
/// Seconde frontière mise en protocole (REFACTORING §3 : « un protocole par
/// frontière d'I/O, une implémentation `Live`, et un bouchon par protocole »),
/// et **délibérément distincte de `FilePicking`** : celle-ci choisit un
/// dossier, celle-là un fichier image. Les fondre donnerait à
/// `GameEnvironmentStore` une méthode dont il n'a que faire, et obligerait son
/// bouchon à la porter.
///
/// L'implémentation réelle — `LiveImagePicker`, AppKit — vit dans l'app ;
/// Core n'en connaît que ce protocole, Foundation seul.
public protocol ImagePicking {
    /// Ouvre le sélecteur et rend le chemin de l'image choisie, ou `nil` si
    /// l'utilisateur a annulé. Bloquant : le panneau tourne en modal.
    ///
    /// - Parameter title: le titre du panneau, déjà localisé par l'appelant —
    ///   Core ne résout pas de clé.
    func pickImage(title: String) -> String?
}
