import Foundation

/// C5-T1 — la recherche des traductions françaises sur tout le parc, et ce
/// qu'elle a trouvé.
///
/// Lancée **par un bouton**, jamais d'office (choix de l'utilisateur,
/// 2026-09-24) ; les résultats restent sur disque et survivent au redémarrage.
/// Le store vit sur le ViewModel (patron `keybindScanService`) : la page est
/// recréée à chaque changement d'onglet, une recherche en cours ne doit pas
/// mourir avec elle.
///
/// Séquentielle, un mod à la fois : le quota Nexus est de 2 000 requêtes par
/// heure. S'arrête net sur l'absence de clé ou un 429 — enchaîner 175 échecs
/// écraserait des résultats valables par des pannes.
@MainActor
@Observable
final class FrenchTranslationSweepStore {
    enum StopReason: Equatable {
        case noApiKey
        case rateLimited
        case cancelled
    }

    private(set) var entries: [String: FrenchTranslationSweep.Entry]
    private(set) var isRunning = false
    private(set) var done = 0
    private(set) var total = 0
    /// Le mod en cours de recherche, pour la ligne de progression.
    private(set) var currentName: String?
    /// Pourquoi la dernière recherche s'est arrêtée avant la fin, s'il y a lieu.
    private(set) var stopReason: StopReason?

    @ObservationIgnored private var task: Task<Void, Never>?
    /// Le numéro de la recherche en cours. **« Arrêter » ne peut pas compter
    /// sur l'annulation de la tâche** : elle attend une requête réseau dont le
    /// rappel ignore l'annulation, et le bouton restait sans effet tant que la
    /// requête n'avait pas répondu (2026-09-24, figé à 0 / 175). `cancel()`
    /// clôt donc la recherche lui-même et change ce numéro ; la tâche le relit
    /// avant chaque écriture et se tait s'il a changé — sans quoi les
    /// résultats tardifs d'une recherche abandonnée écraseraient ceux de la
    /// suivante.
    @ObservationIgnored private var generation = 0

    init() {
        entries = FrenchTranslationSweep.Storage.load()
    }

    /// La date de la recherche la plus ancienne parmi ces mods — ce que la
    /// page annonce comme « à jour au ».
    func oldestSearch(among candidates: [FrenchTranslationSweep.Candidate]) -> Date? {
        candidates.compactMap { entries[$0.folderName]?.searchedAt }.min()
    }

    /// - Parameter log: la trace de chaque mod (début, durée, issue), vers la
    ///   page Journaux — c'est elle qui dira où une recherche s'attarde.
    func run(_ candidates: [FrenchTranslationSweep.Candidate],
             log: @escaping (String) -> Void) {
        guard !isRunning else { return }
        generation += 1
        let run = generation
        // Sans clé, le premier mod rend `.noApiKey` et la boucle s'arrête
        // avant d'écrire quoi que ce soit : pas de seconde vérification ici.
        stopReason = nil
        isRunning = true
        done = 0
        total = candidates.count
        log("Traductions FR : recherche de \(candidates.count) mods")
        task = Task { [weak self] in
            for candidate in candidates {
                guard let self, self.generation == run else { return }
                self.currentName = candidate.name
                let started = Date()
                let result = await FrenchTranslationLookup.find(name: candidate.name,
                                                                hostModId: candidate.nexusModId)
                // Arrêtée pendant l'attente : rien de ce qui revient ne s'écrit.
                guard self.generation == run else { return }
                let elapsed = String(format: "%.1f s", Date().timeIntervalSince(started))
                switch result {
                case .success(let entry):
                    self.entries[candidate.folderName] = entry
                    log("Traductions FR : \(candidate.name) — \(entry.hits.count) résultat(s), \(elapsed)")
                case .failure(let error):
                    log("Traductions FR : \(candidate.name) — échec \(error), \(elapsed)")
                    switch error {
                    case .noApiKey: self.stopReason = .noApiKey
                    case .rateLimited: self.stopReason = .rateLimited
                    default:
                        // Une panne sur un mod n'arrête pas les autres ; elle
                        // se retient comme panne, jamais comme « rien
                        // trouvé ». Un résultat antérieur valable reste
                        // lisible : on ne l'écrase que s'il n'y en avait pas.
                        if self.entries[candidate.folderName] == nil {
                            self.entries[candidate.folderName] = .init(hits: [], searchedAt: Date(),
                                                                       failed: true)
                        }
                    }
                }
                if self.stopReason != nil { break }
                self.done += 1
                if self.done % 10 == 0 { FrenchTranslationSweep.Storage.save(self.entries) }
            }
            guard let self, self.generation == run else { return }
            log("Traductions FR : terminé, \(self.done) / \(self.total)")
            self.finish()
        }
    }

    /// Clôt la recherche **tout de suite**, sans attendre la requête en vol.
    func cancel() {
        guard isRunning else { return }
        generation += 1
        task?.cancel()
        stopReason = .cancelled
        finish()
    }

    private func finish() {
        FrenchTranslationSweep.Storage.save(entries)
        isRunning = false
        currentName = nil
        task = nil
    }
}
