import Foundation

/// La composition des deux requêtes d'une vérification des mises à jour —
/// le QUOI de `checkNexusUpdates` (le COMMENT — gardes, construction des
/// candidats, application des verdicts, drapeaux de fin — reste au
/// ViewModel).
///
/// Extraite du ViewModel le 2026-09-11 (REFACTORING §5, domaine Nexus,
/// tranche 3), sur le patron `ModDetailRefresh` : les fetchers arrivent en
/// closures (§3) — `SmapiUpdateClient.shared` et
/// `PathoschildCompatibilityList` en production, des stubs en test.
///
/// Les deux requêtes partent **en parallèle** : le filet Pathoschild n'est
/// pas déclenché seulement sur échec de smapi.io, qui répond souvent
/// `success([])` avec un sous-ensemble seulement du parc (478 entrées sur
/// 1 080 envoyées, mesuré sur le parc réel 2026-09-01) et omet
/// silencieusement les `UniqueID` qu'elle ne connaît pas. Le dump porte le
/// `nexusID` local dont la reprise Nexus a besoin pour ces mods.
///
/// L'application n'est appelée **qu'une fois les deux résolues** — sinon
/// smapi.io peut répondre avant le dump, et l'appelant lirait un index
/// Pathoschild vide. En production, l'arrivée est rendue sur `queue`
/// (`.main`) ; en test, une queue locale et des fetchers synchrones
/// suffisent. Les tampons qui capturaient le résultat smapi.io en attendant
/// le dump étaient des propriétés du ViewModel : ce sont ici des variables
/// locales, le type ne publie rien.
enum NexusUpdateCheck {

    /// Une ligne de journal prête à émettre (jumeau de
    /// `NexusResume.JournalLine` — même forme, autre domaine ; le troisième
    /// du dépôt demandera une unification).
    struct JournalLine: Equatable {
        let text: String
        let level: LogLevel
    }

    /// Ce que la composition a décidé — l'appelant applique.
    enum Resolution: Equatable {
        /// smapi.io a répondu. `isComplete` commande l'enregistrement du
        /// succès (une passe amputée n'est pas un passage réussi du parc :
        /// l'enregistrer couperait la vérification automatique pendant
        /// douze heures pour des mods qui n'ont pas été interrogés).
        case applied(isComplete: Bool)
        /// smapi.io a échoué — le repli Pathoschild des verdicts de
        /// compatibilité reste à tenter.
        case failed(SmapiUpdateClient.Failure)
        /// Cas dégradé : la complétion smapi.io n'a jamais eu lieu.
        case noResult
    }

    /// Ce que la composition a constaté, rendu à l'appelant plutôt que
    /// journalisé ici.
    struct Composition {
        let smapiResult: Result<SmapiUpdateClient.Outcome, SmapiUpdateClient.Failure>?
        /// Le parc **tel qu'interrogé**, restitué tel quel.
        let entries: [SmapiUpdateRequest.Entry]
        let folders: [NexusIdLearning.Folder]
        let resolution: Resolution
        /// Le bandeau d'échec de l'écran — `"rate_limited"` sur un 429 (cas
        /// nommé, l'UI le dit autrement), le défaut sinon. `nil` hors échec.
        let checkError: String?
        /// Ce que la composition a eu à dire, dans l'ordre : le filet
        /// limité, la passe incomplète, l'échec, le cas dégradé.
        let journal: [JournalLine]
    }

    /// - Parameters:
    ///   - gameVersion: brute, telle que le journal SMAPI l'a portée — c'est
    ///     ici qu'elle passe par `sanitizedGameVersion`, car une valeur qui
    ///     ne s'analyse pas fait rendre une liste vide à smapi.io : le lot
    ///     entier disparaîtrait sans erreur.
    ///   - queue: la queue sur laquelle la composition est rendue.
    ///   - smapiFetch: la requête groupée. En production :
    ///     `SmapiUpdateClient.shared.fetch`.
    ///   - pathoschildFetch: le filet, rendant « la requête (ou le décodage)
    ///     a échoué et le cache est vide ». En production :
    ///     `PathoschildCompatibilityList.fetch` — l'appelant y garde ses
    ///     effets propres au retour (le dump vient d'être posé : les lignes
    ///     « à savoir » peuvent changer).
    ///   - progress: la progression smapi.io, relayée telle quelle.
    static func run(entries: [SmapiUpdateRequest.Entry],
                    folders: [NexusIdLearning.Folder],
                    gameVersion: String?,
                    queue: DispatchQueue = .main,
                    smapiFetch: @escaping (_ entries: [SmapiUpdateRequest.Entry],
                                           _ gameVersion: String,
                                           _ progress: @escaping (Int, Int) -> Void,
                                           _ completion: @escaping (Result<SmapiUpdateClient.Outcome, SmapiUpdateClient.Failure>) -> Void) -> Void,
                    pathoschildFetch: @escaping (_ completion: @escaping (Bool) -> Void) -> Void,
                    progress: @escaping (Int, Int) -> Void,
                    completion: @escaping (Composition) -> Void) {
        let group = DispatchGroup()
        var pathoschildFetchFailed = false
        var smapiResult: Result<SmapiUpdateClient.Outcome, SmapiUpdateClient.Failure>?
        // Le `notify` est posé **avant** le départ des requêtes : avec des
        // fetchers synchrones en test, le compte atteindrait zéro avant
        // l'enregistrement et la composition ne rendrait jamais. En
        // production les fetchs sont asynchrones et l'ordre est indifférent.
        group.enter()
        group.enter()
        group.notify(queue: queue) {
            var journal: [JournalLine] = []
            if pathoschildFetchFailed {
                journal.append(JournalLine(
                    text: "Dump Pathoschild indisponible (réseau + cache vide) : "
                        + "filet limité à smapi.io",
                    level: .warning))
            }
            var resolution = Resolution.noResult
            var checkError: String? = nil
            switch smapiResult {
            case .success(let outcome)?:
                resolution = .applied(isComplete: outcome.isComplete)
                if !outcome.isComplete {
                    let cause = outcome.failure.map { " — cause : \($0)" } ?? ""
                    journal.append(JournalLine(
                        text: "[MAJ] Passe smapi.io incomplète : \(outcome.batchesCompleted) "
                            + "lot(s) sur \(outcome.batchesTotal)\(cause) — les mods des lots "
                            + "restants gardent leurs lignes précédentes, et la prochaine "
                            + "vérification automatique repartira au lieu d'attendre 12 h",
                        level: .warning))
                }
            case .failure(let failure)?:
                resolution = .failed(failure)
                // Le 429 est nommé : l'écran dit « limitation de débit »
                // plutôt qu'une interpolation d'enum.
                checkError = if case .http(429) = failure { "rate_limited" } else { "\(failure)" }
                journal.append(JournalLine(
                    text: "Vérification des mises à jour en échec : \(failure)",
                    level: .warning))
            case .none:
                // Cas dégradé : ni smapi.io ni la complétion n'ont été appelées.
                journal.append(JournalLine(
                    text: "Vérification terminée sans résultat smapi.io",
                    level: .warning))
            }
            completion(Composition(
                smapiResult: smapiResult,
                entries: entries,
                folders: folders,
                resolution: resolution,
                checkError: checkError,
                journal: journal))
        }

        pathoschildFetch { failed in
            pathoschildFetchFailed = failed
            group.leave()
        }
        smapiFetch(entries, SmapiUpdateRequest.sanitizedGameVersion(gameVersion),
                   progress) { result in
            smapiResult = result
            group.leave()
        }
    }
}
