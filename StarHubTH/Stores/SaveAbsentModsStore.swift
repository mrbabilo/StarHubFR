import Foundation
import Observation

/// A1-T9 — les mods **disparus du parc** que la sauvegarde affichée a
/// connus. Extrait du VM (règle F1-T2). Le calcul vit dans `SaveAbsentMods`
/// (Core, testé) ; ici, le fil de conduite — le même que
/// `SavePausedFootprintStore`, sur le scan **partagé** de la fiche
/// (`SaveFingerprintScanCache`) : la résolution se refait quand le parc
/// change, sans relire la save.
@MainActor
@Observable
final class SaveAbsentModsStore {

    enum State: Equatable {
        case idle
        case scanning
        case unreadable
        case loaded([AbsentModFootprint])
    }

    private(set) var state: State = .idle

    /// Un résultat n'atterrit que s'il répond à la dernière demande —
    /// changer de sauvegarde pendant un scan ne doit jamais afficher les
    /// mods de la précédente.
    private var generation = 0

    /// La save lue en dernier (nom + date). Quand elle change, l'ancienne
    /// liste ne vaut plus rien : après un nettoyage, la remontrer pendant
    /// le rescan ferait croire que rien n'a été retiré. Un changement du
    /// seul parc, lui, garde l'affichage jusqu'au nouveau résultat.
    private var lue: (folderName: String, modified: Date)?

    /// `modified` : la date qui sert de clé au cache — celle de la save par
    /// défaut, une plus récente quand l'app vient de réécrire le fichier
    /// (A1-T10 : la fiche garde l'instantané d'avant le nettoyage).
    func refresh(save: SaveGameInfo, mods: [ModItem], modified: Date? = nil) {
        generation += 1
        let demande = generation
        let date = modified ?? save.lastModified
        if case .idle = state { state = .scanning }
        if let lue, lue.folderName != save.folderName || lue.modified != date {
            state = .scanning
        }
        lue = (save.folderName, date)
        let url = save.fileURL
        Task {
            let scan = await SaveFingerprintScanCache.shared.scan(
                folderName: save.folderName, modified: date, url: url)
            let entries = scan.map { SaveAbsentMods.entries(scan: $0, mods: mods) }
            guard demande == generation else { return }
            state = entries.map(State.loaded) ?? .unreadable
        }
    }
}
