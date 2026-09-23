import Foundation
import Observation

/// A1-T6 — ce que la sauvegarde affichée porte des mods **en pause**, pour
/// sa fiche. Extrait du VM (règle F1-T2). Le calcul vit dans
/// `SavePausedFootprints` (Core, testé) ; ici, le fil de conduite.
///
/// Deux coûts distincts : le **scan** (une save dépasse 40 Mo de XML) se
/// garde en cache par dossier et date de modification ; la **résolution**
/// (≈ 1 000 UniqueIDs contre des milliers d'empreintes) se refait quand le
/// parc change — une bascule rafraîchit la section sans relire la save.
/// Les deux tournent hors du fil principal.
@MainActor
@Observable
final class SavePausedFootprintStore {

    enum State: Equatable {
        case idle
        case scanning
        case unreadable
        case loaded([PausedModFootprint])
    }

    private(set) var state: State = .idle

    /// La demande en cours : un résultat n'atterrit que s'il répond à la
    /// **dernière** — changer de sauvegarde pendant un scan ne doit jamais
    /// afficher les mods de la précédente.
    private var generation = 0
    private var cachedScan: (folderName: String, modified: Date, scan: SaveFingerprintScan?)?

    func refresh(save: SaveGameInfo, mods: [ModItem]) {
        generation += 1
        let demande = generation
        let cache = cachedScan.flatMap {
            $0.folderName == save.folderName && $0.modified == save.lastModified ? $0 : nil
        }
        if cache == nil { state = .scanning }
        let url = save.fileURL
        Task {
            let (scan, entries) = await Task.detached(priority: .userInitiated) {
                var scan: SaveFingerprintScan?
                if let cache {
                    scan = cache.scan
                } else {
                    do {
                        scan = SaveFingerprintScanner.scan(try Data(contentsOf: url))
                    } catch {
                        scan = nil // illisible → l'état le dit, rien n'est inventé
                    }
                }
                return (scan, scan.map { SavePausedFootprints.entries(scan: $0, mods: mods) })
            }.value
            guard demande == generation else { return }
            cachedScan = (save.folderName, save.lastModified, scan)
            state = entries.map(State.loaded) ?? .unreadable
        }
    }
}
