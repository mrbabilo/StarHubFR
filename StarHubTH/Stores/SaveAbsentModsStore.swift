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

    func refresh(save: SaveGameInfo, mods: [ModItem]) {
        generation += 1
        let demande = generation
        if case .idle = state { state = .scanning }
        let url = save.fileURL
        Task {
            let scan = await SaveFingerprintScanCache.shared.scan(
                folderName: save.folderName, modified: save.lastModified, url: url)
            let entries = scan.map { SaveAbsentMods.entries(scan: $0, mods: mods) }
            guard demande == generation else { return }
            state = entries.map(State.loaded) ?? .unreadable
        }
    }
}
