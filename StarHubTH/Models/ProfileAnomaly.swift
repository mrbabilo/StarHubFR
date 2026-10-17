import Foundation

/// P5-9 (audit UX 2026-10-16) — l'état anormal qu'une rangée de profil
/// signale, avec son remède. Les remèdes existaient déjà ; il manquait le
/// témoin : une application incomplète n'avait qu'une modale de fin, une
/// désynchronisation des configs que le journal, une application
/// interrompue qu'un dialogue au lancement.
enum ProfileAnomaly: Equatable {
    /// Le journal R2 nomme ce profil : une application a été coupée net.
    case interruptedApply
    /// La dernière application a laissé des dossiers à leur ancienne place.
    case incompletelyApplied
    /// Profil actif dont les `config.json` n'ont pas été réécrits (bascule
    /// faite jeu ouvert).
    case configsDesynced

    /// Une seule pastille, la plus grave : l'interruption tient le parc dans
    /// un état mêlé, l'application incomplète laisse des dossiers mal placés,
    /// la désynchronisation ne touche que des réglages.
    static func of(profileId: UUID, isActive: Bool, journalProfileId: UUID?,
                   incomplete: Set<UUID>, desyncedId: UUID?) -> ProfileAnomaly? {
        if journalProfileId == profileId { return .interruptedApply }
        if incomplete.contains(profileId) { return .incompletelyApplied }
        if isActive, desyncedId == profileId { return .configsDesynced }
        return nil
    }
}
