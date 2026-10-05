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
/// **Incrémentale depuis le 2026-10-05** (`FrenchTranslationSweep
/// .shouldRescan`) : un parc stable se relit au cache — ~90 minutes pour tout
/// balayer, dont 90 % sans résultat, ne servaient qu'une fois. `forceAll`
/// refait tout, pour la main qui veut être sûre.
///
/// **Deux chercheurs** (moitiés du tableau, borné à deux) : ~×2 sur un
/// balayage complet, marge large sous le quota Nexus de 2 000 requêtes/heure
/// (~500 par passage). S'arrête net sur l'absence de clé ou un 429 — chaque
/// chercheur relit `stopReason` **avant chaque requête** : après un 429 reçu
/// par l'un, l'autre n'en envoie plus.
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
    /// Les mods en cours de recherche — jusqu'à deux chercheurs, la ligne de
    /// progression nomme les deux (un seul nom ferait passer le second
    /// chercheur pour du silence).
    private(set) var currentNames: [String] = []
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

    /// Combien de ces mods parlent encore à leur cache (dans la fenêtre de
    /// re-balayage, signature intacte) : l'en-tête le dit — un « à jour au »
    /// global mentirait dès qu'un passage incrémental ne re-cherche qu'une
    /// partie du parc.
    func freshCount(among candidates: [FrenchTranslationSweep.Candidate], now: Date = Date()) -> Int {
        candidates.filter {
            !FrenchTranslationSweep.shouldRescan(candidate: $0,
                                                 previous: entries[$0.folderName], now: now)
        }.count
    }

    /// - Parameters:
    ///   - forceAll: re-chercher **tout**, cache frais compris (le menu,
    ///     contre le bouton qui suit `shouldRescan`).
    ///   - log: la trace de chaque mod (début, durée, issue), vers la
    ///     page Journaux — c'est elle qui dira où une recherche s'attarde.
    func run(_ candidates: [FrenchTranslationSweep.Candidate],
             forceAll: Bool = false,
             log: @escaping (String) -> Void) {
        guard !isRunning else { return }
        generation += 1
        let run = generation
        // Sans clé, le premier mod rend `.noApiKey` et la boucle s'arrête
        // avant d'écrire quoi que ce soit : pas de seconde vérification ici.
        stopReason = nil
        let due = forceAll ? candidates : candidates.filter {
            FrenchTranslationSweep.shouldRescan(candidate: $0,
                                                previous: entries[$0.folderName], now: Date())
        }
        isRunning = true
        done = 0
        total = due.count
        if total == 0 {
            log("Traductions FR : rien à re-balayer — le cache couvre \(candidates.count) mod(s)")
            finish()
            return
        }
        log("Traductions FR : \(forceAll ? "re-balayage total" : "re-balayage") de \(total) "
            + "mod(s) sur \(candidates.count) en cache")
        task = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                // Deux chercheurs, chacun sa moitié : borné à deux requêtes
                // en vol, sans sémaphore ni file à inventer.
                let half = (due.count + 1) / 2
                for slice in [due.prefix(half), due.suffix(due.count - half)] {
                    group.addTask {
                        await self?.scanHalf(Array(slice), run: run, log: log)
                    }
                }
            }
            guard let self, self.generation == run else { return }
            log("Traductions FR : terminé, \(self.done) / \(self.total)")
            self.finish()
        }
    }

    /// La moitié d'un chercheur : un mod après l'autre, en relisant
    /// `stopReason` **avant chaque requête** — après un 429 reçu par l'autre
    /// moitié, celle-ci n'en envoie plus.
    private func scanHalf(_ slice: [FrenchTranslationSweep.Candidate],
                          run: Int, log: @escaping (String) -> Void) async {
        for candidate in slice {
            guard generation == run, stopReason == nil else { return }
            await search(candidate, run: run, log: log)
        }
    }

    /// Un mod, par le chercheur qui l'a pris : chercher, écrire, compter.
    private func search(_ candidate: FrenchTranslationSweep.Candidate,
                        run: Int, log: @escaping (String) -> Void) async {
        currentNames.append(candidate.name)
        defer { currentNames.removeAll { $0 == candidate.name } }
        let started = Date()
        let result = await FrenchTranslationLookup.find(name: candidate.name,
                                                        hostModId: candidate.nexusModId)
        // Arrêtée pendant l'attente : rien de ce qui revient ne s'écrit.
        guard generation == run, stopReason == nil else { return }
        let elapsed = String(format: "%.1f s", Date().timeIntervalSince(started))
        switch result {
        case .success(let entry):
            entries[candidate.folderName] = .init(
                hits: entry.hits, linkedModIds: entry.linkedModIds,
                searchedAt: entry.searchedAt, failed: entry.failed,
                signature: candidate.signature)
            log("Traductions FR : \(candidate.name) — \(entry.hits.count) résultat(s), \(elapsed)")
        case .failure(let error):
            log("Traductions FR : \(candidate.name) — échec \(error), \(elapsed)")
            switch error {
            case .noApiKey: stopReason = .noApiKey
            case .rateLimited: stopReason = .rateLimited
            default:
                // Une panne sur un mod n'arrête pas les autres ; elle
                // se retient comme panne, jamais comme « rien
                // trouvé ». Un résultat antérieur valable reste
                // lisible : on ne l'écrase que s'il n'y en avait pas.
                if entries[candidate.folderName] == nil {
                    entries[candidate.folderName] = .init(hits: [], searchedAt: Date(),
                                                          failed: true)
                }
            }
        }
        done += 1
        if done % 10 == 0 { FrenchTranslationSweep.Storage.save(entries) }
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
        currentNames = []
        task = nil
    }
}
