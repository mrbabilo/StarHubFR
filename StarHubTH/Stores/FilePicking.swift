import Foundation

/// Une frontière d'I/O — le sélecteur de dossiers du système. Premier
/// protocole du dépôt (REFACTORING §3 : « un protocole par frontière
/// d'I/O, une implémentation `Live`, et un bouchon par protocole », le
/// tout dans le même commit). `NSOpenPanel` appelé en ligne depuis le
/// ViewModel rendait `selectGameDir` intestable — le défaut que l'amont
/// documentait déjà (§8, leur 3.4).
///
/// L'implémentation réelle — `LiveFilePicker`, AppKit — vit dans l'app ;
/// Core n'en connaît que ce protocole, Foundation seul.
public protocol FilePicking {
    /// Ouvre le sélecteur de dossier et rend le chemin choisi, ou `nil` si
    /// l'utilisateur a annulé. Bloquant : le panneau tourne en modal.
    func pickDirectory() -> String?
}
