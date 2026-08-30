import Foundation

/// Ce qu'une `ModCard` peut servir depuis un mod **installé**.
///
/// La carte de grille reste telle quel (spec refonte §6 : « le composant
/// reste tel quel, son alimentation change ») : cet adaptateur est le seul
/// endroit qui sait ce qu'un `ModItem` peut et ne peut pas nourrir. Un mod
/// installé n'a pas d'endossements servis, et sa catégorie ne passe pas par
/// ici (`NexusCategory` vit côté app, hors du target Core — la vue la résout
/// par `vm.category(for:)`).
///
/// La **vignette**, elle, existe : le cache Nexus persisté (`nexusCachedExtras`)
/// porte une `pictureUrl` pour 769 de ses 791 entrées, mesuré sur le parc
/// réel — aucun réseau supplémentaire n'est nécessaire pour la connaître.
/// L'adaptateur ne la va pas chercher (c'est le ViewModel qui tient le cache),
/// il la reçoit et la convertit.
///
/// Les en-têtes de pack portent des sentinelles (`version: ""`,
/// `author: "Group"`, `StarHubTHViewModel.swift:2738`) : l'adaptateur agrège
/// depuis les enfants, en pur — même sémantique que
/// `displayAuthor`/`displayVersion` du ViewModel, sans leur repli Nexus
/// (dépend du cache de mise à jour, hors d'une carte compacte).
public enum ModGridCardValues {
    /// L'état d'un mod installé, servi **toujours** : un état ne se code pas
    /// par la présence ou l'absence d'un ornement (spec refonte P6). La vue
    /// pose le libellé localisé, la teinte et le glyph ; ici on ne dit que
    /// lequel des deux.
    public enum State: Sendable, Equatable {
        case active
        case paused
    }

    public struct Card: Equatable, Sendable {
        public let title: String
        public let subtitle: String
        public let thumbnailURL: URL?
        public let state: State
        public let neutralBadge: String?
        public let endorsements: Int?
    }

    /// - Parameters:
    ///   - mod: le mod installé, tel que servi par `vm.mods` — en-tête de
    ///     pack compris.
    ///   - versionPrefix: la clé de format de version localisée déjà rendue
    ///     par `vm.L(L10n.Mods.versionPrefix)` — passée en valeur pour
    ///     garder la fonction pure et testable sans ViewModel.
    ///   - pictureURL: l'adresse de la capture Nexus en cache pour ce mod,
    ///     résolue par `sharedNexusId(of:effectiveId:)` puis lue dans
    ///     `nexusModExtras`. Absente, vide ou illisible : le rectangle gris
    ///     de la carte tient la place, rien ne se décale.
    public static func card(mod: ModItem,
                            versionPrefix: String,
                            pictureURL: String? = nil) -> Card {
        let items = mod.isGroup ? (mod.children ?? []) : [mod]
        let author = sharedValue(of: items, \.author)
        let version = sharedValue(of: items, \.version)
            .map { String(format: versionPrefix, $0) }
        return Card(title: mod.name,
                    subtitle: [version, author].compactMap { $0 }
                        .joined(separator: " · "),
                    thumbnailURL: pictureURL.flatMap {
                        $0.isEmpty ? nil : URL(string: $0)
                    },
                    state: mod.isEnabled ? .active : .paused,
                    neutralBadge: mod.languages.contains("fr") ? "FR" : nil,
                    endorsements: nil)
    }

    /// L'identifiant Nexus qui donne droit à une image — `nil` quand aucun ne
    /// représente honnêtement la carte.
    ///
    /// Un en-tête de pack est fabriqué avec `nexusModId: ""`
    /// (`StarHubTHViewModel.swift:2738`) : sans règle, une carte de pack
    /// n'aurait jamais d'image. Prendre celui du **premier enfant qui en a
    /// un** — ce que fait `resolvedNexusModId` pour la fiche, où l'utilisateur
    /// a demandé ce pack-là — donnerait en revanche à un pack **à plat** (des
    /// mods sans rapport rangés dans un même dossier, 19 dans le parc réel)
    /// la capture d'écran de son premier composant, présentée comme la
    /// sienne. D'où la même règle que l'auteur et la version : seul compte ce
    /// que **tous** les enfants partagent.
    ///
    /// - Parameter effectiveId: l'identifiant propre d'un mod, saisi par
    ///   l'utilisateur ou lu du manifeste (`vm.effectiveNexusModId(for:)`),
    ///   injecté pour garder la règle pure.
    public static func sharedNexusId(of mod: ModItem,
                                     effectiveId: (ModItem) -> String) -> String? {
        let own = effectiveId(mod)
        if !own.isEmpty { return own }
        guard mod.isGroup, let children = mod.children else { return nil }
        let ids = Set(children.map(effectiveId).filter { !$0.isEmpty })
        return ids.count == 1 ? ids.first : nil
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
