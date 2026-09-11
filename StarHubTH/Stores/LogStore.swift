import Foundation
import Observation

/// Le journal affiché — **les deux sources confondues** : les lignes que
/// StarHubFR écrit lui-même (`log(_:level:)`, 76 sites du ViewModel et 10 des
/// vues) et le bloc relu depuis `SMAPI-latest.txt`.
///
/// D'où son nom : ce n'est pas un store « SMAPI ». La santé de SMAPI
/// (diagnostics, date, fraîcheur, conflits, historique d'erreurs) est un
/// second domaine, et une tranche à part.
///
/// Ce qu'il ne fait pas : lire le fichier, le parser, imputer une ligne à un
/// mod. `parseAndAppendSmapiLog` reste au ViewModel — elle a besoin de `mods`
/// et de `resolveModFolder`, c'est-à-dire du domaine Scan, extrait en dernier.
@Observable
final class LogStore {

    private(set) var entries: [LogEntry] = []

    /// Plafond mémoire : un rechargement SMAPI peut ajouter des centaines de
    /// lignes, et une session longue en empilerait sans fin.
    ///
    /// Public parce que le ViewModel s'en sert pour borner le **travail** de
    /// la passe d'imputation, avant que le store n'applique le plafond de
    /// l'affichage.
    static let defaultCap = 2000

    @ObservationIgnored private let cap: Int

    init(cap: Int = LogStore.defaultCap) {
        self.cap = cap
    }

    func append(_ entry: LogEntry) {
        entries = LogBudget.appending(entry, to: entries, cap: cap)
    }

    /// Vide ce que StarHubFR a écrit, et **garde** le bloc SMAPI : celui-ci
    /// est relu d'un fichier, l'effacer ne ferait que le faire revenir au
    /// prochain rechargement — et entre-temps la liste contredirait la carte
    /// de santé, qui parse le même fichier.
    func clearApp() {
        entries.removeAll { $0.source == .app }
    }

    /// Un rechargement **remplace** le bloc SMAPI (le fichier est un
    /// instantané unique), et le budget se compte sur ce que les entrées de
    /// l'app laissent — voir `LogBudget`, qui porte les deux règles et leurs
    /// deux bugs historiques.
    func replaceSmapi(with incoming: [LogEntry]) {
        entries = LogBudget.replacingSmapi(in: entries, with: incoming, cap: cap)
    }
}
