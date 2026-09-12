import Testing
import Foundation
@testable import StarHubTHCore

/// L'état de la couverture française **par profil** (B3-T4) : les résumés
/// publiés, la passe de mesure, et le cache qui survit à la session.
///
/// Les règles du domaine sont en Core et testées (`ProfileTranslationCoverage`,
/// `TranslationCoverageCache`) ; le store les porte. Ce qu'il épine : le
/// **test-et-pose** de la passe (la page peut réapparaître pendant une
/// mesure — un second lancement ne doit rien relancer), et un cache lu
/// **une fois** par session.
///
/// Le disque arrive par closures (patron du dépôt) : aucun test n'écrit dans
/// le vrai Application Support.
@Suite struct ProfileTranslationStoreTests {

    private func summary(translated: Int, total: Int) -> ProfileTranslationSummary {
        .init(translatableCount: 1, fullyTranslatedCount: translated > 0 ? 1 : 0,
              totalKeys: total, translatedKeys: translated, pending: [])
    }

    /// Une empreinte valide — `TranslationStamp.init` n'est pas public, il se
    /// fabrique depuis des dossiers ; ici une constante suffit, le test ne
    /// juge pas l'empreinte.
    private let stamp = TranslationStamp(fileCount: 1, totalSize: 10, newestModified: 100)

    /// Le disque en lecture seule : le store ne l'ecrit plus, il rend ce
    /// qu'il faut ecrire et l'appelant s'en charge hors du fil principal.
    private final class FakeCache {
        private(set) var loadCount = 0
        var stored: [String: TranslationCoverageCache.Entry] = [:]

        func load(from url: URL) -> [String: TranslationCoverageCache.Entry] {
            loadCount += 1
            return stored
        }
    }

    private func store(_ cache: FakeCache) -> ProfileTranslationStore {
        ProfileTranslationStore(loadCache: cache.load(from:))
    }

    // MARK: - Le verrou de la passe

    @Test func theFirstMeasureTakesTheLock() {
        let s = store(FakeCache())
        #expect(s.beginMeasure() == true)
        #expect(s.isMeasuring)
    }

    @Test func aSecondMeasureIsRefusedWhileTheFirstRuns() {
        // La page des profils peut réapparaître pendant qu'une mesure tourne.
        let s = store(FakeCache())
        _ = s.beginMeasure()
        #expect(s.beginMeasure() == false)
        s.endMeasure()
        #expect(s.isMeasuring == false)
        #expect(s.beginMeasure() == true)
    }

    // MARK: - Le cache, lu une fois par session

    @Test func theCacheIsLoadedOnceThenServedFromMemory() {
        let cache = FakeCache()
        cache.stored = ["deja": .init(stamp: stamp, total: 5, translated: 2)]
        let s = store(cache)
        let url = URL(fileURLWithPath: "/tmp/hub.json")
        s.loadCacheIfNotLoaded(from: url)
        // Ce qui est lu **atterrit** dans l'etat : c'est la garantie qui
        // epargne les 15,7 s d'analyse au lancement. Compter les lectures ne
        // la tient pas — sans cette attente, `_ = loadCache(url)` passe.
        #expect(s.cacheEntries["deja"]?.total == 5)
        s.loadCacheIfNotLoaded(from: url)
        #expect(cache.loadCount == 1)
    }

    @Test func aMissingCacheURLMarksTheSessionLoadedWithoutReading() {
        // Pas d'URL (Application Support introuvable) : ne pas reessayer à
        // chaque affichage de la page, ça ne deviendra pas vrai.
        let cache = FakeCache()
        let s = store(cache)
        s.loadCacheIfNotLoaded(from: nil)
        #expect(cache.loadCount == 0)
        s.loadCacheIfNotLoaded(from: URL(fileURLWithPath: "/tmp/hub.json"))
        #expect(cache.loadCount == 0)
    }

    // MARK: - La fusion du mesuré

    @Test func mergingPublishesCoverageAndCacheEntries() {
        let s = store(FakeCache())
        s.mergeMeasured(["modA": .init(total: 10, translated: 4, missing: [], empty: [], orphan: [], identicalToSource: [])],
                        entries: ["modA": .init(stamp: stamp, total: 10, translated: 4)])
        #expect(s.coverage["modA"]?.translated == 4)
        #expect(s.cacheEntries["modA"]?.total == 10)
    }

    // MARK: - L'invalidation, l'élagage

    /// Traduire un mod ne doit plus jamais échouer à changer le pourcentage
    /// des profils qui le contiennent : l'invalidation passe par la clé que
    /// le calcul lit.
    @Test func invalidatingDropsTheCoverageOfThatUniqueId() {
        let s = store(FakeCache())
        s.mergeMeasured(["moda": .init(total: 10, translated: 4, missing: [], empty: [], orphan: [], identicalToSource: [])],
                        entries: [:])
        s.invalidate(uniqueId: "ModA")       // la clé est normalisée en minuscules
        #expect(s.coverage["moda"] == nil)
    }

    /// Le cache sur disque ne doit pas grossir avec les mods désinstallés.
    @Test func pruningKeepsOnlyTheInstalledAndReturnsWhatWasWritten() {
        let cache = FakeCache()
        let s = store(cache)
        s.mergeMeasured(["garde": .init(total: 1, translated: 1, missing: [], empty: [], orphan: [], identicalToSource: [])],
                        entries: ["garde": .init(stamp: stamp, total: 1, translated: 1),
                                  "parti": .init(stamp: stamp, total: 2, translated: 2)])
        let written = s.pruneCache(keeping: ["garde"])
        // L'appelant écrit ce qui est rendu ; l'état est déjà élagué.
        #expect(Array(written.keys) == ["garde"])
        #expect(s.cacheEntries["parti"] == nil)
    }
}
