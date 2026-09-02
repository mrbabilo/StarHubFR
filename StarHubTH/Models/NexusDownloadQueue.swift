import Foundation

/// File FIFO des téléchargements Nexus destinés à la feuille d'installation.
///
/// Un téléchargement en vol à la fois reste la règle — deux se disputeraient
/// `pendingDownloadedZip` — mais une demande arrivée pendant qu'un autre
/// tourne, ou pendant que la feuille d'installation est ouverte, n'est plus
/// refusée : elle attend ici son tour. La logique vit en Core pour être
/// testable ; le ViewModel ne porte que les points de branchement (mise en
/// file, drainage aux bascules de repos).
struct NexusDownloadQueue: Equatable {
    /// Paramètres du téléchargeur, origine neutralisée : un lien `nxm://`
    /// et un bouton in-app aboutissent au même entrant.
    struct Entry: Equatable {
        let modId: Int
        let fileId: Int?
        let game: String
        var key: String?
        var expires: Int?
    }

    private(set) var entries: [Entry] = []

    var isEmpty: Bool { entries.isEmpty }

    /// Ajoute en fin de file et retourne vrai si l'entrée est nouvelle.
    ///
    /// Un clic répété sur le **même fichier** (modId + fileId + game
    /// identiques) ne duplique pas : il rafraîchit la clé de l'entrée déjà
    /// en attente — un lien `nxm://` re-cliqué porte une clé plus fraîche
    /// que le précédent, c'est elle qui doit survivre. ⚠️ Garde étroite :
    /// deux fichiers *différents* du même mod, ou le même fichier sur un
    /// autre domaine de jeu, sont des demandes distinctes — elles doivent
    /// toutes passer.
    @discardableResult
    mutating func enqueue(_ entry: Entry) -> Bool {
        if let index = entries.firstIndex(where: {
            $0.modId == entry.modId && $0.fileId == entry.fileId && $0.game == entry.game
        }) {
            entries[index].key = entry.key
            entries[index].expires = entry.expires
            return false
        }
        entries.append(entry)
        return true
    }

    /// Défile le premier entré, s'il y en a un.
    mutating func dequeue() -> Entry? {
        guard !entries.isEmpty else { return nil }
        return entries.removeFirst()
    }
}
