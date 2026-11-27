import Foundation

/// Ce qu'une partie ouvre à l'éditeur, en **une** lecture (A0) : le sac et
/// l'empreinte du fichier lu. Une seconde lecture relirait la partie entière
/// et remplacerait l'empreinte qui garde l'écriture du sac.
struct SaveContents: Sendable {
    var inventory: [InventoryItem]
    let stamp: SaveDocument.Stamp

    /// Lecture au fond ; remise `@MainActor` **synchrone**, pour que la garde
    /// anti-course de `NavigationStore.setEditingSave` lise l'état exact.
    typealias Loader = @Sendable (SaveGameInfo, @escaping @MainActor @Sendable (SaveContents?) -> Void) -> Void
}
