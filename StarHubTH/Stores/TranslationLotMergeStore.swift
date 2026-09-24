import Foundation
import Observation

/// C3-T5 — la fusion entre humains (règle F1-T2 : hors VM).
///
/// Un lot peut revenir d'un traducteur alors que le mod a déjà été traduit
/// par un autre chemin : la fusion juge chaque entrée contre l'état courant
/// **complet** (`TranslationLotMerge`, en Core et testé) et ce store porte la
/// session — les comptes rendus par mod, les penchants d'arbitrage, l'écrit-
/// ure retenue. La relecture est **hors du fil principal** (Task.detached) ;
/// l'écriture passe par la closure fournie par la vue, qui la branche sur le
/// chemin éprouvé du ViewModel (`saveTranslation`) — le store ne connaît ni
/// le VM ni le disque des mods.
@MainActor
@Observable
final class TranslationLotMergeStore {

    /// Un mod du lot, relu. `takeIncoming` porte le penchant par identité
    /// (`TranslationLotImport.identity`) — il ne concerne que les
    /// `.divergent` ; un `.writeNow` s'écrit sans décision, un `.identical`
    /// et un `.unfilled` ne s'écrivent jamais.
    struct ModReview: Identifiable {
        let mod: ModItem
        let review: TranslationLotMerge.Review
        var takeIncoming: [String: Bool]

        var id: String { mod.folderName }

        /// Ce qui s'écrirait maintenant : écritures directes + divergences
        /// penchées « prendre le sien ».
        var writableCount: Int {
            review.proposals.filter { proposal in
                switch proposal.disposition {
                case .writeNow: return true
                case .divergent: return takeIncoming[identity(of: proposal)] == true
                case .identical, .unfilled: return false
                }
            }.count
        }

        var divergenceCount: Int {
            review.proposals.filter { $0.disposition == .divergent }.count
        }

        func identity(of proposal: TranslationLotMerge.Proposal) -> String {
            TranslationLotImport.identity(proposal.component, proposal.key)
        }
    }

    /// Ce qu'une écriture a produit, pour le dire. `dropped` porte les
    /// divergences dont l'anglais a bougé pendant la feuille ouverte : elles
    /// sont nommées, jamais écrites sur l'ancien anglais.
    struct Outcome: Equatable {
        let written: Int
        let failures: Int
        let dropped: [String]
        let refusals: [String: TranslationLotMerge.FileRefusal]
    }

    private(set) var reviews: [ModReview] = []
    private(set) var busy = false

    /// Relit chaque fichier contre l'état courant de son mod. Les refus de
    /// fichier (mauvais mod, mauvaise langue, lot qui ne touche rien) rendent
    /// ici, par mod — un mod en échec n'empêche pas les autres. Rend
    /// `true` quand la session porte quelque chose à montrer : au moins un
    /// mod relu, un refus, ou un mod inconnu à nommer.
    @discardableResult
    func prepare(entries: [(mod: ModItem, data: Data, rows: [TranslationCoverage.DiffRow])],
                 unknownFolders: [String] = []) async -> Bool {
        busy = true
        defer { busy = false }
        var reviews: [ModReview] = []
        var refusals: [String: TranslationLotMerge.FileRefusal] = [:]
        for entry in entries {
            let folder = entry.mod.folderName
            let review: Result<TranslationLotMerge.Review, TranslationLotMerge.FileRefusal> =
                await Task.detached(priority: .userInitiated) {
                    do {
                        return .success(try TranslationLotMerge.review(
                            entry.data, rows: entry.rows,
                            mod: folder, language: "fr"))
                    } catch let refusal as TranslationLotMerge.FileRefusal {
                        return .failure(refusal)
                    } catch {
                        return .failure(.unreadable)
                    }
                }.value
            switch review {
            case .success(let review):
                reviews.append(ModReview(mod: entry.mod, review: review,
                                         takeIncoming: [:]))
            case .failure(let refusal):
                refusals[folder] = refusal
            }
        }
        self.reviews = reviews
        self.refusals = refusals
        self.unknownFolders = unknownFolders
        return !reviews.isEmpty || !refusals.isEmpty || !unknownFolders.isEmpty
    }

    /// Les refus de fichier de la dernière `prepare`, par dossier de mod.
    private(set) var refusals: [String: TranslationLotMerge.FileRefusal] = [:]

    /// Les dossiers que le parc ne connaît pas — un lot arrive pour un mod
    /// absent (désinstallé, renommé). Nommés, jamais bloquants.
    private(set) var unknownFolders: [String] = []

    /// Penche toutes les divergences d'un mod d'un coup.
    func leanAll(_ modID: String, incoming: Bool) {
        guard let review = reviews.first(where: { $0.id == modID }) else { return }
        var updated = review
        for proposal in review.review.proposals where proposal.disposition == .divergent {
            updated.takeIncoming[review.identity(of: proposal)] = incoming
        }
        reviews = reviews.map { $0.id == modID ? updated : $0 }
    }

    /// Penche une divergence — `nil` la rend indécise, donc non écrite.
    func lean(_ modID: String, identity: String, incoming: Bool?) {
        reviews = reviews.map { review in
            guard review.id == modID else { return review }
            var updated = review
            if let incoming {
                updated.takeIncoming[identity] = incoming
            } else {
                updated.takeIncoming.removeValue(forKey: identity)
            }
            return updated
        }
    }

    /// Écrit ce qui est retenu, par le chemin fourni. **La re-vérification
    /// vit ici** : entre la feuille ouverte et le clic, le mod a pu bouger —
    /// chaque proposition est résolue contre les rangées **fraîches** que
    /// l'appelant vient de relire, et une ligne dont l'anglais n'est plus le
    /// même est abandonnée et nommée, jamais écrite sur l'ancien anglais.
    ///
    /// `writer` reçoit le mod, la rangée fraîche, la valeur et reçoit le
    /// comportement du chemin d'écriture du VM (`saveTranslation` avec
    /// `clearingReviewFlag: false`) ; les drapeaux « À relire » sont posés
    /// ici, une fois par mod, sur tout ce qui a été écrit.
    func apply(modID: String,
               freshRows: [TranslationCoverage.DiffRow],
               writer: (ModItem, TranslationCoverage.DiffRow, String) -> StarHubTHViewModel.SaveOutcome)
        -> Outcome {
        guard let review = reviews.first(where: { $0.id == modID }) else {
            return Outcome(written: 0, failures: 0, dropped: [], refusals: [:])
        }
        var byIdentity: [String: TranslationCoverage.DiffRow] = [:]
        for row in freshRows {
            byIdentity[TranslationLotImport.identity(row.component, row.key)] = row
        }
        var written = 0
        var failures = 0
        var dropped: [String] = []
        var flags: [TranslationBaseline.ReviewFlag] = []
        for proposal in review.review.proposals {
            let identity = review.identity(of: proposal)
            let take: Bool
            switch proposal.disposition {
            case .writeNow: take = true
            case .divergent: take = review.takeIncoming[identity] == true
            case .identical, .unfilled: take = false
            }
            guard take else { continue }
            guard let fresh = byIdentity[identity] else {
                dropped.append(proposal.key)
                continue
            }
            guard fresh.english == proposal.source else {
                dropped.append(proposal.key)
                continue
            }
            switch writer(review.mod, fresh, proposal.incoming) {
            case .saved:
                written += 1
                flags.append(.init(component: proposal.component, key: proposal.key,
                                   source: proposal.source, target: proposal.incoming))
            case .blocked, .failed:
                failures += 1
            }
        }
        if !flags.isEmpty, let store = TranslationBaseline.defaultDirectory() {
            do {
                try TranslationBaseline.setReviewNeeded(flags, modFolderName: modID, in: store)
            } catch {
                // L'écriture a réussi ; le drapeau « À relire » perdu se
                // retrouvera au prochain calcul du diff. Ne pas faire
                // échouer l'ensemble pour un magasin de drapeaux.
            }
        }
        reviews.removeAll { $0.id == modID }
        return Outcome(written: written, failures: failures, dropped: dropped,
                       refusals: [:])
    }

    /// Referme la session sans rien écrire.
    func reset() {
        reviews = []
        refusals = [:]
        unknownFolders = []
    }
}
