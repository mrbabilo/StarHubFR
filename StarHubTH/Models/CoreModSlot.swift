import Foundation

/// L'état d'une extension de base (SMAPI, Content Patcher, SpaceCore…) tel que
/// l'accueil l'affiche.
enum CoreModStatus {
    case enabledAndInstalled
    case installedButDisabled
    case notInstalled
}

/// Une extension de base et le mod qui l'occupe, s'il y en a un.
///
/// Ce type vivait dans `Views/HomeView.swift` alors qu'il ne porte aucune
/// présentation : une donnée rangée dans la couche vue, donc hors de portée des
/// tests. Voir la règle de couche du plan de refactorisation.
struct CoreModSlot {
    let status: CoreModStatus
    let mod: ModItem?

    /// L'occupant d'une extension de base, choisi parmi les mods dont le nom
    /// contient `keyword`.
    ///
    /// La cascade compte : plusieurs mods peuvent porter « content patcher »
    /// dans leur nom — le mod lui-même, un pack qui l'étend, une traduction. On
    /// préfère donc, dans l'ordre : le nom **exact** et activé, puis n'importe
    /// lequel d'activé, puis le nom exact même en pause, puis le premier venu.
    /// Sans cette hiérarchie, l'accueil peut annoncer « installé et actif » en
    /// désignant une traduction pendant que le mod, lui, est en pause.
    static func resolve(keyword: String, among mods: [ModItem]) -> CoreModSlot {
        let matches = mods.filter { $0.name.lowercased().contains(keyword) }
        guard !matches.isEmpty else { return CoreModSlot(status: .notInstalled, mod: nil) }

        let exactEnabled = matches.first { $0.name.lowercased() == keyword && $0.isEnabled }
        let anyEnabled = matches.first(where: \.isEnabled)
        let exactAny = matches.first { $0.name.lowercased() == keyword }
        // `matches` n'est pas vide : le dernier recours ne peut pas échouer.
        guard let mod = exactEnabled ?? anyEnabled ?? exactAny ?? matches.first else {
            return CoreModSlot(status: .notInstalled, mod: nil)
        }
        return CoreModSlot(status: mod.isEnabled ? .enabledAndInstalled : .installedButDisabled,
                           mod: mod)
    }
}
