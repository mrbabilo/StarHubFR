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
/// heure, et un mod coûte 2 à 4 requêtes (176 composants sur le parc).
/// S'arrête net sur l'absence de clé ou un 429 — enchaîner 176 échecs
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

    init() {
        entries = FrenchTranslationSweep.Storage.load()
    }

    /// La date de la recherche la plus ancienne parmi ces mods — ce que la
    /// page annonce comme « à jour au ».
    func oldestSearch(among candidates: [FrenchTranslationSweep.Candidate]) -> Date? {
        candidates.compactMap { entries[$0.folderName]?.searchedAt }.min()
    }

    func run(_ candidates: [FrenchTranslationSweep.Candidate]) {
        guard !isRunning else { return }
        // Sans clé, le premier mod rend `.noApiKey` et la boucle s'arrête
        // avant d'écrire quoi que ce soit : pas de seconde vérification ici.
        stopReason = nil
        isRunning = true
        done = 0
        total = candidates.count
        task = Task { [weak self] in
            for candidate in candidates {
                guard let self, !Task.isCancelled else { break }
                self.currentName = candidate.name
                let result = await FrenchTranslationLookup.find(name: candidate.name,
                                                                hostModId: candidate.nexusModId)
                switch result {
                case .success(let entry):
                    self.entries[candidate.folderName] = entry
                case .failure(.noApiKey):
                    self.stopReason = .noApiKey
                case .failure(.rateLimited):
                    self.stopReason = .rateLimited
                case .failure:
                    // Une panne sur un mod n'arrête pas les autres ; elle se
                    // retient comme panne, jamais comme « rien trouvé ». Un
                    // résultat antérieur valable reste lisible : on ne
                    // l'écrase que s'il n'y en avait pas.
                    if self.entries[candidate.folderName] == nil {
                        self.entries[candidate.folderName] = .init(hits: [], searchedAt: Date(),
                                                                   failed: true)
                    }
                }
                if self.stopReason != nil { break }
                self.done += 1
                if self.done % 10 == 0 { FrenchTranslationSweep.Storage.save(self.entries) }
            }
            guard let self else { return }
            if Task.isCancelled, self.stopReason == nil { self.stopReason = .cancelled }
            FrenchTranslationSweep.Storage.save(self.entries)
            self.isRunning = false
            self.currentName = nil
            self.task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }
}
