import Foundation

/// Comment trier les sauvegardes affichées.
public enum SaveSortOption: String, Codable, Sendable {
    case name
    case lastPlayed
    case money
}

/// Reconstruit l'arborescence des sauvegardes à partir de leurs seuls noms de
/// dossier.
///
/// Stardew ne consigne aucun lien de parenté : quand on dérive une partie depuis
/// une sauvegarde, le nouveau dossier porte le nom de l'ancien suivi d'un
/// suffixe. `Farm_1_2` descend donc de `Farm_1` — mais **seulement si**
/// `Farm_1` existe encore, sinon la coupure est plus haut, ou il n'y en a pas.
/// C'est cette règle, invisible et jamais vérifiée, qui décide de la forme de
/// l'arbre affiché.
///
/// Extrait du ViewModel (`savesHierarchy`), où le filtre par étiquette et les
/// notes de sauvegarde restent — ils dépendent d'un magasin sur disque.
enum SaveTree {
    /// Le nom du dossier parent, ou `nil` si la sauvegarde est une racine.
    ///
    /// On coupe au dernier `_` et on remonte tant qu'aucun candidat n'existe :
    /// un nom de ferme peut lui-même contenir des `_`, donc s'arrêter au premier
    /// découpage inventerait des parents qui n'existent pas.
    static func parentFolderName(of folderName: String,
                                 among existing: Set<String>) -> String? {
        var candidate = folderName
        while let separator = candidate.range(of: "_", options: .backwards) {
            candidate = String(candidate[..<separator.lowerBound])
            if existing.contains(candidate) { return candidate }
        }
        return nil
    }

    /// L'arbre complet, racines triées et enfants triés récursivement.
    static func build(from saves: [SaveGameInfo], sortedBy order: SaveSortOption) -> [SaveNode] {
        let names = Set(saves.map(\.folderName))
        var childrenByParent: [String: [SaveGameInfo]] = [:]
        var roots: [SaveGameInfo] = []

        for save in saves {
            if let parent = parentFolderName(of: save.folderName, among: names) {
                childrenByParent[parent, default: []].append(save)
            } else {
                roots.append(save)
            }
        }

        func node(for save: SaveGameInfo) -> SaveNode {
            SaveNode(info: save,
                     children: sort(childrenByParent[save.folderName, default: []].map(node), by: order))
        }
        return sort(roots.map(node), by: order)
    }

    /// Trie une fratrie, ses enfants étant déjà triés par construction.
    static func sort(_ nodes: [SaveNode], by order: SaveSortOption) -> [SaveNode] {
        nodes.sorted { a, b in
            switch order {
            case .name:
                return a.info.playerName.localizedCaseInsensitiveCompare(b.info.playerName) == .orderedAscending
            case .lastPlayed:
                return a.info.lastModified > b.info.lastModified
            case .money:
                return a.info.money > b.info.money
            }
        }
    }
}
