import Foundation
import Observation

/// L'état de la couverture française **par profil** (B3-T4) : ce que chaque
/// profil affichera en français une fois appliqué, la passe de mesure, et le
/// cache qui survit à la session.
///
/// **Store séparé de `frenchCoverageByMod`, délibérément** (commentaire du
/// ViewModel, préservé) : le cache de la liste ne contient que les mods qui
/// livrent *déjà* du français, et l'absence d'entrée y signifie « pas encore
/// mesuré ». Les mods qui font tout l'intérêt de cet écran ont un
/// `default.json` et **aucun** `fr.json` — les verser dans le cache commun
/// ferait surgir une pastille « 0 % » sur autant de lignes de la liste.
///
/// Ce qu'il épine : le **test-et-pose** de la passe (la page peut
/// réapparaître pendant une mesure) et un cache lu **une fois** par session.
/// Le disque arrive par closures — aucun appelant n'écrit dans le vrai
/// Application Support à l'improviste.
@Observable
final class ProfileTranslationStore {

    /// Le résumé de chaque profil mesuré — le signal de rendu.
    private(set) var summaries: [UUID: ProfileTranslationSummary] = [:]

    /// Vrai pendant une passe de mesure : la page montre un témoin plutôt
    /// qu'un pourcentage faux.
    private(set) var isMeasuring = false

    /// `UniqueID` en minuscules → couverture propre au mod. Interne de
    /// travail : aucune vue ne le lit, le signal de rendu est `summaries`.
    @ObservationIgnored private(set) var coverage: [String: TranslationCoverage.Coverage] = [:]
    @ObservationIgnored private(set) var cacheEntries: [String: TranslationCoverageCache.Entry] = [:]
    @ObservationIgnored private(set) var cacheLoaded = false

    @ObservationIgnored private let loadCache: (URL) -> [String: TranslationCoverageCache.Entry]
    @ObservationIgnored private let saveCache: ([String: TranslationCoverageCache.Entry], URL) -> Void

    init(loadCache: @escaping (URL) -> [String: TranslationCoverageCache.Entry]
            = { TranslationCoverageCache.load(from: $0) },
         saveCache: @escaping ([String: TranslationCoverageCache.Entry], URL) -> Void
            = { TranslationCoverageCache.save($0, to: $1) }) {
        self.loadCache = loadCache
        self.saveCache = saveCache
    }

    // MARK: - Lecture

    /// Le résumé d'un profil, quand il a été mesuré.
    func summary(for id: UUID) -> ProfileTranslationSummary? {
        summaries[id]
    }

    // MARK: - La passe de mesure

    /// Prend le verrou de mesure, ou rend `false` si une passe tourne —
    /// la page des profils peut réapparaître pendant qu'une mesure tourne.
    func beginMeasure() -> Bool {
        if isMeasuring { return false }
        isMeasuring = true
        return true
    }

    func endMeasure() {
        isMeasuring = false
    }

    /// Charge le cache, **une fois** par session. Sans URL, la session est
    /// quand même marquée chargée : réessayer à chaque affichage ne
    /// deviendrait pas vrai.
    func loadCacheIfNotLoaded(from url: URL?) {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let url else { return }
        cacheEntries = loadCache(url)
    }

    /// Publie ce que la passe a mesuré — la couverture et le cache d'un coup.
    func mergeMeasured(_ measured: [String: TranslationCoverage.Coverage],
                       entries: [String: TranslationCoverageCache.Entry]) {
        coverage.merge(measured) { _, new in new }
        cacheEntries.merge(entries) { _, new in new }
    }

    /// Retire la couverture d'un identifiant — traduire un mod doit changer
    /// le pourcentage des profils qui le contiennent.
    func invalidate(uniqueId: String) {
        coverage.removeValue(forKey: uniqueId.lowercased())
    }

    /// Élagge le cache des mods désinstallés, **écrit**, et met l'état à
    /// jour. Rend ce qui a été écrit.
    @discardableResult
    func pruneCache(keeping installedIds: Set<String>, to url: URL)
    -> [String: TranslationCoverageCache.Entry] {
        let entries = TranslationCoverageCache.pruned(cacheEntries, keeping: installedIds)
        cacheEntries = entries
        saveCache(entries, url)
        return entries
    }

    // MARK: - Publication

    func setSummaries(_ newSummaries: [UUID: ProfileTranslationSummary]) {
        summaries = newSummaries
    }
}
