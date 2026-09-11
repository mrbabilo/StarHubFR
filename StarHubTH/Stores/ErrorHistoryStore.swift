import Foundation
import Observation

/// L'historique d'erreurs par mod et par version, tel qu'il s'accumule d'un
/// journal SMAPI au suivant.
///
/// **La règle centrale est une garde contre une perte de données** : tant que
/// l'historique n'a pas été lu du disque, rien ne doit le muter — le muter
/// reviendrait à écrire un historique vide par-dessus le fichier. Elle vivait
/// au ViewModel sous la forme de deux `if errorHistoryLoaded` posés au point
/// d'appel, qu'un troisième appelant aurait pu oublier ; ici, c'est le type
/// qui la tient, et aucun appelant ne peut la contourner.
///
/// Les I/O arrivent par closures (patron du dépôt) : la persistance réelle est
/// `ModErrorHistoryStore`, et le store n'a pas à la connaître — c'est ce qui
/// le rend testable sans écrire dans le vrai Application Support.
///
/// Ce qu'il ne fait pas : décider **si** un journal doit être replié, ni
/// quelles lignes en retenir. Ces deux décisions vivent dans
/// `SmapiHealthFold`, où elles sont prouvées.
@Observable
final class ErrorHistoryStore {

    private(set) var history = ModErrorHistory()
    /// Date du dernier journal replié, pour ne jamais compter le même deux
    /// fois. L'appelant la passe à `SmapiHealthFold.shouldFold`.
    private(set) var lastFoldedDate: Date?

    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private let loadFromDisk: () -> (history: ModErrorHistory, lastLogDate: Date?)
    @ObservationIgnored private let saveToDisk: (ModErrorHistory, Date?) -> Bool
    /// Ce qu'on fait d'une écriture ratée. Posé après construction — le
    /// ViewModel le branche sur son journal, et il ne peut pas se passer
    /// lui-même à son propre `init`. Même patron que
    /// `NexusMetadataStore.setOnInvalidate` : un crochet unique, et le poser
    /// deux fois remplace le premier.
    @ObservationIgnored private var onWriteFailure: () -> Void = {}

    init(load: @escaping () -> (history: ModErrorHistory, lastLogDate: Date?)
            = { ModErrorHistoryStore.load() },
         save: @escaping (ModErrorHistory, Date?) -> Bool
            = { ModErrorHistoryStore.save($0, lastLogDate: $1) },
         onWriteFailure: @escaping () -> Void = {}) {
        self.loadFromDisk = load
        self.saveToDisk = save
        self.onWriteFailure = onWriteFailure
    }

    /// Pose le crochet d'échec d'écriture. Voir `onWriteFailure`.
    func setOnWriteFailure(_ handler: @escaping () -> Void) {
        onWriteFailure = handler
    }

    /// Lit le fichier, une seule fois. Un second appel ne relit pas :
    /// l'historique en mémoire fait foi, et le relire écraserait ce qui n'a
    /// pas encore été persisté.
    func loadIfNeeded() {
        guard !isLoaded else { return }
        let loaded = loadFromDisk()
        history = loaded.history
        lastFoldedDate = loaded.lastLogDate
        isLoaded = true
    }

    /// Replie un journal : enregistre ses observations et avance la date.
    ///
    /// **Un journal sans observation avance quand même la date** — sinon il
    /// serait relu et réexaminé à chaque ouverture d'onglet.
    func fold(_ observations: [ModErrorHistory.Observation], at date: Date) {
        guard isLoaded else { return }
        if !observations.isEmpty {
            history.merge(observations, at: date)
        }
        lastFoldedDate = date
        persist()
    }

    /// Suit un mod qui change de dossier. N'écrit que si quelque chose a
    /// bougé — un mod sans historique ne coûte pas une écriture disque.
    func rename(from old: String, to new: String, shared: Bool) {
        guard isLoaded else { return }
        if ModFolderRename.migrate(&history.mods, from: old, to: new, shared: shared) {
            persist()
        }
    }

    /// Oublie un mod parti à la corbeille : sans ça, le fichier grossit
    /// indéfiniment avec des mods qui ne sont plus installés.
    func forget(mod: String) {
        guard isLoaded else { return }
        history.remove(mod: mod)
        persist()
    }

    /// L'historique s'accumule et ne se rebâtit pas — le journal SMAPI suivant
    /// écrase le précédent. Une panne d'écriture doit se dire : sans ça, elle
    /// ne se verrait qu'au lancement suivant, et par une perte.
    private func persist() {
        if !saveToDisk(history, lastFoldedDate) { onWriteFailure() }
    }
}
