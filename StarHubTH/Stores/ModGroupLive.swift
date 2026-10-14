import Foundation

/// I-T21 lot 2 — le magasin des groupes, un par ViewModel, sans état stocké
/// dans le ViewModel (F1-T2, patron `GuidedPilotLive`).
extension StarHubTHViewModel {
    var groups: ModGroupStore { ModGroupLive.store(for: self) }
}

@MainActor
enum ModGroupLive {
    @MainActor private static var stores: [ObjectIdentifier: ModGroupStore] = [:]

    static func store(for viewModel: StarHubTHViewModel) -> ModGroupStore {
        let key = ObjectIdentifier(viewModel)
        if let existing = stores[key] { return existing }
        // Le magasin naît souvent pendant le rendu de la liste : le journal,
        // état observé, s'écrit au tour suivant, jamais en plein rendu.
        let created = ModGroupStore(directory: AppSupport.directory, log: { [weak viewModel] message in
            Task { @MainActor in viewModel?.log(message, level: .warning) }
        })
        stores[key] = created
        return created
    }
}
