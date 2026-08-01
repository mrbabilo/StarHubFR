import Foundation

/// Ce qui manque à un mod pour tourner, d'après l'état des mods installés.
///
/// Extrait du ViewModel, où rien ne le testait — alors que ces deux calculs
/// commandent le filtre « Problèmes » de la liste et les avertissements de la
/// fiche mod. Ils s'appuient sur les index reconstruits à chaque scan, passés
/// ici en paramètre : c'est ce qui les rend vérifiables.
///
/// **Les dépendances facultatives sont ignorées** dans les deux cas : un mod
/// tourne sans elles, les signaler noierait les vraies pannes.
enum ModDependencyStatus {
    /// Les dépendances requises qu'aucun mod installé ne fournit.
    ///
    /// La comparaison se fait en minuscules : SMAPI compare les identifiants
    /// sans égard à la casse, et deux auteurs écrivent rarement le même
    /// identifiant de la même façon.
    static func missing(for mod: ModItem, installedIds: Set<String>) -> [String] {
        mod.dependencies.compactMap { dep in
            guard dep.isRequired else { return nil }
            return installedIds.contains(dep.uniqueId.lowercased()) ? nil : dep.uniqueId
        }
    }

    /// Les dépendances requises qui sont installées mais en pause. Aussi
    /// bloquantes qu'une absence : le mod ne tournera pas davantage.
    static func disabled(for mod: ModItem, states: [String: Bool]) -> [String] {
        mod.dependencies.compactMap { dep in
            guard dep.isRequired else { return nil }
            let key = dep.uniqueId.lowercased()
            // Absente de l'index : elle n'est pas installée du tout, donc elle
            // relève de `missing(for:installedIds:)`, pas d'ici.
            guard let enabled = states[key], !enabled else { return nil }
            return dep.uniqueId
        }
    }
}
