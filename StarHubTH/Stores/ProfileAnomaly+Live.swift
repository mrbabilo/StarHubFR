import Foundation

/// P5-9 — ce que la rangée d'un profil lit et déclenche. La règle vit dans
/// `ProfileAnomaly` (Core) ; ceci la nourrit et appelle les remèdes qui
/// existaient déjà. Hors du fichier du ViewModel (règle F1-T2).
extension StarHubTHViewModel {
    func profileAnomaly(for profile: ModProfile) -> ProfileAnomaly? {
        let store = profilesStore
        return ProfileAnomaly.of(profileId: profile.id, isActive: store.activeProfileId == profile.id,
                                 journalProfileId: unresolvedApplyJournal?.profileId,
                                 incomplete: store.incompletelyAppliedIds,
                                 desyncedId: store.configsDesyncedId)
    }

    func remedy(_ anomaly: ProfileAnomaly, for profile: ModProfile) {
        switch anomaly {
        case .interruptedApply:
            // Le dialogue du lancement (R2) : reprendre ou garder le disque.
            surfaceApplyRecoveryIfNeeded()
        case .incompletelyApplied:
            // Sur le profil actif et incomplet, l'aiguillage rend `.resume`.
            applyProfile(id: profile.id)
        case .configsDesynced:
            // Le jeu relit ses configs au lancement : réécrire sous lui ne
            // servirait à rien, et la marque resterait posée.
            guard !isGameRunning() else {
                showModal(message: localization.L(L10n.ProfileAnomaly.desyncGameRunning))
                return
            }
            restoreProfileConfigs(for: profile.id)
            profilesStore.setConfigsDesynced(nil)
        }
    }
}
