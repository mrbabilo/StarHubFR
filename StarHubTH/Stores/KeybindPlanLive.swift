import Foundation

/// Plan de raccourcis — le service et le magasin des familles, un par
/// ViewModel, sans état stocké dans le ViewModel (F1-T2, patron
/// `ModGroupLive`). Pas une propriété `let` du VM : son initialiseur ne peut
/// pas capturer `isGameRunning()` du VM, et `StarHubTHViewModel.swift` est
/// verrouillé à sa taille par le cliquet.
extension StarHubTHViewModel {
    var keybindPlanService: KeybindPlanService { KeybindPlanLive.service(for: self) }
    var keybindFamilyStore: KeybindFamilyStore { KeybindPlanLive.familyStore(for: self) }
}

@MainActor
enum KeybindPlanLive {
    @MainActor private static var services: [ObjectIdentifier: KeybindPlanService] = [:]
    @MainActor private static var familyStores: [ObjectIdentifier: KeybindFamilyStore] = [:]

    static func service(for viewModel: StarHubTHViewModel) -> KeybindPlanService {
        let key = ObjectIdentifier(viewModel)
        if let existing = services[key] { return existing }
        // `ModConfigBackupManager()` vise le même dossier que l'instance
        // partagée. Jeu inconnu (VM disparu) = refus, comme `GuidedPilotLive`.
        let created = KeybindPlanService(backupManager: ModConfigBackupManager(),
                                         isGameRunning: { [weak viewModel] in viewModel?.isGameRunning() ?? true })
        services[key] = created
        return created
    }

    static func familyStore(for viewModel: StarHubTHViewModel) -> KeybindFamilyStore {
        let key = ObjectIdentifier(viewModel)
        if let existing = familyStores[key] { return existing }
        // Le magasin naît souvent pendant le rendu : le journal, état observé,
        // s'écrit au tour suivant, jamais en plein rendu.
        let created = KeybindFamilyStore(directory: AppSupport.directory, log: { [weak viewModel] message in
            Task { @MainActor in viewModel?.log(message, level: .warning) }
        })
        familyStores[key] = created
        return created
    }
}
