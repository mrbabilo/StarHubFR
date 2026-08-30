import Foundation

/// Ce qu'une `ModCard` peut servir depuis un mod **installé**.
///
/// La carte de grille reste telle quel (spec refonte §6 : « le composant
/// reste tel quel, son alimentation change ») : cet adaptateur est le seul
/// endroit qui sait ce qu'un `ModItem` peut et ne peut pas nourrir. Un mod
/// installé n'a ni vignette servie — le `ModDetailCache` n'est pas déroulé
/// pour une grille de 966 mods — ni endossements, ni catégorie Nexus servie,
/// ni pastille « installé » : tout l'est.
///
/// Les en-têtes de pack portent des sentinelles (`version: ""`,
/// `author: "Group"`, `StarHubTHViewModel.swift:2738`) : l'adaptateur agrège
/// depuis les enfants, en pur — même sémantique que
/// `displayAuthor`/`displayVersion` du ViewModel, sans leur repli Nexus
/// (dépend du cache de mise à jour, hors d'une carte compacte).
public enum ModGridCardValues {
    public struct Card: Equatable, Sendable {
        public let title: String
        public let subtitle: String
        public let thumbnailURL: URL?
        public let installedLabel: String?
        public let neutralBadge: String?
        public let endorsements: Int?
    }

    /// - Parameters:
    ///   - mod: le mod installé, tel que servi par `vm.mods` — en-tête de
    ///     pack compris.
    ///   - versionPrefix: la clé de format de version localisée déjà rendue
    ///     par `vm.L(L10n.Mods.versionPrefix)` — passée en valeur pour
    ///     garder la fonction pure et testable sans ViewModel.
    public static func card(mod: ModItem, versionPrefix: String) -> Card {
        let items = mod.isGroup ? (mod.children ?? []) : [mod]
        let author = sharedValue(of: items, \.author)
        let version = sharedValue(of: items, \.version)
            .map { String(format: versionPrefix, $0) }
        return Card(title: mod.name,
                    subtitle: [version, author].compactMap { $0 }
                        .joined(separator: " · "),
                    thumbnailURL: nil,
                    installedLabel: nil,
                    neutralBadge: mod.languages.contains("fr") ? "FR" : nil,
                    endorsements: nil)
    }

    /// La valeur que tous les items partagent — `nil` s'ils divergent ou
    /// n'en ont aucune : la carte compacte préfère ne rien dire plutôt que
    /// de choisir à la place du lecteur. Vide et « Unknown » ne comptent
    /// pas comme des valeurs.
    private static func sharedValue(of items: [ModItem],
                                    _ keyPath: KeyPath<ModItem, String>) -> String? {
        let values = Set(items.map { $0[keyPath: keyPath] }
            .filter { !$0.isEmpty && $0 != "Unknown" })
        return values.count == 1 ? values.first : nil
    }
}
