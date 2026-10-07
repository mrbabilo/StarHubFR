import Foundation
import Observation

/// A3-T8 — l'approbation Nexus des mods, vue de la fiche : l'état de chaque
/// mod du compte (lu une fois par session, à la première fiche Nexus), le
/// geste en cours et le dernier refus. La règle (chemins, formulaire, lecture
/// des réponses) vit dans `NexusEndorsement` (Core, testé).
///
/// La réponse brute de chaque geste part au journal : la forme des réponses
/// vient du client officiel, pas d'une mesure ; la première vraie réponse doit
/// pouvoir se relire.
@MainActor @Observable
final class NexusEndorsementStore {
    private(set) var statuses: [Int: NexusEndorsement.Status] = [:]
    private(set) var inFlight: Set<Int> = []
    /// Le dernier refus par mod, effacé au geste suivant.
    private(set) var failures: [Int: NexusEndorsement.Outcome] = [:]
    @ObservationIgnored private var listRequested = false
    @ObservationIgnored private let checker: NexusUpdateChecker

    init(checker: NexusUpdateChecker = .shared) {
        self.checker = checker
    }

    /// Clé retirée : rien de ce compte ne doit survivre.
    func reset() {
        statuses = [:]
        failures = [:]
        listRequested = false
    }

    func loadIfNeeded(log: (String) -> Void) async {
        guard !listRequested, let key = checker.apiKey(), !key.isEmpty,
              let request = NexusRequestBuilder.makeRequest(path: NexusEndorsement.listPath, apiKey: key)
        else { return }
        listRequested = true
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse { checker.noteQuota(from: http) }
            guard let map = NexusEndorsement.statuses(from: data) else {
                listRequested = false
                log("Nexus endorsements: réponse illisible (\(String(decoding: data.prefix(200), as: UTF8.self)))")
                return
            }
            statuses = map
        } catch {
            listRequested = false
            log("Nexus endorsements: \(error.localizedDescription)")
        }
    }

    /// Approuve, ou s'abstient si le mod l'est déjà.
    func toggle(modId: Int, version: String, log: (String) -> Void) async {
        guard !inFlight.contains(modId), let key = checker.apiKey(), !key.isEmpty else { return }
        let endorse = statuses[modId] != .endorsed
        guard let request = NexusRequestBuilder.makeJSONPost(
            path: NexusEndorsement.path(modId: modId, endorse: endorse), apiKey: key,
            body: NexusEndorsement.body(version: version)) else { return }
        inFlight.insert(modId)
        failures[modId] = nil
        defer { inFlight.remove(modId) }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let http = response as? HTTPURLResponse { checker.noteQuota(from: http) }
            log("Nexus \(endorse ? "endorse" : "abstain") \(modId): HTTP \(code) "
                + String(decoding: data.prefix(300), as: UTF8.self))
            switch NexusEndorsement.outcome(from: data, httpStatus: code) {
            case .endorsed: statuses[modId] = .endorsed
            case .abstained: statuses[modId] = .abstained
            case let refusal: failures[modId] = refusal
            }
        } catch {
            failures[modId] = .unknown(httpStatus: 0, message: error.localizedDescription)
        }
    }
}
