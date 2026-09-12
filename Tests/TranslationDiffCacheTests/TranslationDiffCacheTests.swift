import Testing
import Foundation
@testable import StarHubTHCore

/// Le cache des rangées de diff (F7) : ce qu'il garde, ce qu'il refuse de
/// garder, et ce qui l'invalide.
///
/// Ce qu'il achète est mesuré (ROADMAP F7) : 1 205 à 2 569 ms de calcul
/// contre 0,2 à 0,4 ms d'empreinte. Ce qui se teste ici, c'est qu'il ne
/// serve jamais les rangées d'un mod pour un autre.
@Suite struct TranslationDiffCacheTests {

    private func stamp(_ size: Int, count: Int = 1, modified: Int = 100) -> TranslationStamp {
        TranslationStamp(fileCount: count, totalSize: size, newestModified: modified)
    }

    private func rows(_ keys: String...) -> [TranslationCoverage.DiffRow] {
        keys.map { TranslationCoverage.DiffRow(key: $0, english: "en", french: "",
                                               state: .missing) }
    }

    private func dir(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/parc/\(name)")
    }

    // MARK: - Garder et resservir

    @Test func keptRowsComeBackForTheSameStamp() {
        let cache = TranslationDiffCache()
        cache.store(rows("a", "b"), forModAt: dir("Mod"), stamp: stamp(10))
        #expect(cache.rows(forModAt: dir("Mod"), stamp: stamp(10))?.count == 2)
    }

    /// Le fichier a changé : l'empreinte diffère, le calcul doit reprendre.
    @Test func aChangedStampInvalidatesTheEntry() {
        let cache = TranslationDiffCache()
        cache.store(rows("a"), forModAt: dir("Mod"), stamp: stamp(10))
        #expect(cache.rows(forModAt: dir("Mod"), stamp: stamp(11)) == nil)
    }

    // MARK: - L'invalidation explicite

    /// L'empreinte seule ne voit pas tout : une correction de **même longueur**
    /// dans la **même seconde** la laisse identique — le piège que documente
    /// `removeAll()`. L'invalidation explicite doit l'emporter sur l'empreinte :
    /// c'est l'appel que fait `invalidateFrenchCoverage(for:)` après toute
    /// écriture dans les fichiers d'un mod.
    @Test func removeAllDropsEvenAnEntryTheStampWouldStillServe() {
        let cache = TranslationDiffCache()
        cache.store(rows("a"), forModAt: dir("Mod"), stamp: stamp(10))
        cache.removeAll()
        #expect(cache.rows(forModAt: dir("Mod"), stamp: stamp(10)) == nil)
    }

    /// Vider ne doit pas abîmer le cache pour la suite : le mod réapparaît
    /// avec de nouvelles rangées dès le prochain calcul.
    @Test func removeAllLeavesAUsableCache() {
        let cache = TranslationDiffCache()
        cache.store(rows("a"), forModAt: dir("Mod"), stamp: stamp(10))
        cache.removeAll()
        cache.store(rows("b", "c"), forModAt: dir("Mod"), stamp: stamp(11))
        #expect(cache.rows(forModAt: dir("Mod"), stamp: stamp(11))?.count == 2)
    }

    // MARK: - Ce qu'il refuse de garder

    /// **Le cas qui porte.** Sans fichier de traduction, l'empreinte est
    /// `nil` — et une entrée rangée sous cette absence vaudrait pour
    /// n'importe quel autre mod sans traduction. Rien ne s'écrit, rien ne se
    /// lit.
    @Test func anAbsentStampIsNeverStoredNorServed() {
        let cache = TranslationDiffCache()
        cache.store(rows("a"), forModAt: dir("SansTraduction"), stamp: nil)
        #expect(cache.rows(forModAt: dir("SansTraduction"), stamp: nil) == nil)
        // Et il ne doit pas non plus resservir pour un autre mod sans
        // traduction — le defaut que l'absence d'empreinte provoquerait.
        #expect(cache.rows(forModAt: dir("AutreSansTraduction"), stamp: nil) == nil)
    }

    /// Une entrée valide ne doit jamais sortir sur une demande sans empreinte.
    @Test func aValidEntryIsNotServedToAStamplessLookup() {
        let cache = TranslationDiffCache()
        cache.store(rows("a"), forModAt: dir("Mod"), stamp: stamp(10))
        #expect(cache.rows(forModAt: dir("Mod"), stamp: nil) == nil)
    }

    // MARK: - Deux dossiers, deux entrées

    /// `X` actif et `.X` en pause portent le **même** `folderName` et sont
    /// deux dossiers distincts — cas réel du parc. La clé est le chemin :
    /// les confondre servirait les rangées du mod en pause pour l'actif.
    @Test func thePausedAndActiveFoldersDoNotShareAnEntry() {
        let cache = TranslationDiffCache()
        cache.store(rows("actif"), forModAt: dir("Mod"), stamp: stamp(10))
        cache.store(rows("pause", "pause2"), forModAt: dir(".Mod"), stamp: stamp(10))
        #expect(cache.rows(forModAt: dir("Mod"), stamp: stamp(10))?.map(\.key) == ["actif"])
        #expect(cache.rows(forModAt: dir(".Mod"), stamp: stamp(10))?.count == 2)
    }

    // MARK: - La borne

    /// Une entrée pèse 1,1 à 2,3 Mo sur le parc réel : le cache est borné, et
    /// c'est le **moins récemment utilisé** qui part.
    @Test func theLeastRecentlyUsedEntryIsEvicted() {
        let cache = TranslationDiffCache(capacity: 2)
        cache.store(rows("un"), forModAt: dir("A"), stamp: stamp(1))
        cache.store(rows("deux"), forModAt: dir("B"), stamp: stamp(2))
        // A est relu : c'est B qui devient le plus ancien.
        _ = cache.rows(forModAt: dir("A"), stamp: stamp(1))
        cache.store(rows("trois"), forModAt: dir("C"), stamp: stamp(3))
        #expect(cache.rows(forModAt: dir("A"), stamp: stamp(1)) != nil)
        #expect(cache.rows(forModAt: dir("B"), stamp: stamp(2)) == nil)
        #expect(cache.rows(forModAt: dir("C"), stamp: stamp(3)) != nil)
    }

    /// Ré-enregistrer le même dossier ne consomme pas deux places.
    @Test func storingTheSameFolderTwiceKeepsOneSlot() {
        let cache = TranslationDiffCache(capacity: 2)
        cache.store(rows("v1"), forModAt: dir("A"), stamp: stamp(1))
        cache.store(rows("v2"), forModAt: dir("A"), stamp: stamp(2))
        cache.store(rows("b"), forModAt: dir("B"), stamp: stamp(3))
        #expect(cache.rows(forModAt: dir("A"), stamp: stamp(2))?.map(\.key) == ["v2"])
        #expect(cache.rows(forModAt: dir("B"), stamp: stamp(3)) != nil)
    }

    // MARK: - Le point d'entrée unique, sur de vrais fichiers

    /// Le second appel ne relit pas : l'empreinte est la même. Et il rend
    /// **les mêmes** rangées — un cache qui sert autre chose serait pire que
    /// pas de cache.
    @Test func theCachedEntryPointServesTheSameRowsWithoutRecomputing() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("diffcache-\(UUID().uuidString)")
        let i18n = root.appendingPathComponent("i18n")
        try FileManager.default.createDirectory(at: i18n, withIntermediateDirectories: true)
        try #"{"cle.une":"One","cle.deux":"Two"}"#
            .write(to: i18n.appendingPathComponent("default.json"), atomically: true,
                   encoding: .utf8)
        try #"{"cle.une":"Un"}"#
            .write(to: i18n.appendingPathComponent("fr.json"), atomically: true,
                   encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = TranslationDiffCache()
        let fr = i18n.appendingPathComponent("fr.json")
        let first = TranslationCoverage.diffRows(forModAt: root, locale: "fr", cache: cache)
        #expect(first.count == 2)
        #expect(first.first { $0.key == "cle.une" }?.french == "Un")

        // ⚠️ Comparer deux appels identiques ne prouve **rien** : le calcul est
        // déterministe, il rendrait la même chose sans cache (premier jet de ce
        // test, passé sous le sabotage « ne rien garder »). Ce qui le prouve
        // est de changer le fichier **sans changer son empreinte** — même
        // nombre d'octets, même date à la seconde : si les rangées gardent
        // l'ancienne valeur, c'est qu'elles viennent du cache.
        let stampBefore = TranslationStamp.of(
            directories: I18nLocaleResolver.i18nDirectories(inModDirectory: root))
        let date = try FileManager.default.attributesOfItem(atPath: fr.path)[.modificationDate] as? Date
        try #"{"cle.une":"XX"}"#.write(to: fr, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: date ?? Date()],
                                              ofItemAtPath: fr.path)
        #expect(TranslationStamp.of(
            directories: I18nLocaleResolver.i18nDirectories(inModDirectory: root)) == stampBefore,
                "l'empreinte devait rester identique pour que ce test discrimine")

        let second = TranslationCoverage.diffRows(forModAt: root, locale: "fr", cache: cache)
        #expect(second.first { $0.key == "cle.une" }?.french == "Un",
                "le cache n'a pas servi : la valeur relue est celle du disque")

        // Et maintenant un vrai changement : l'empreinte porte la taille, donc
        // un contenu plus long suffit — le cache doit lâcher.
        try #"{"cle.une":"Un","cle.deux":"Deux","cle.trois":"Trois"}"#
            .write(to: fr, atomically: true, encoding: .utf8)
        let third = TranslationCoverage.diffRows(forModAt: root, locale: "fr", cache: cache)
        #expect(third.count == 3)          // la clé orpheline apparaît
    }

    /// Un mod **sans** fichier de traduction passe par le calcul à chaque
    /// fois — et ne pollue pas le cache d'une entrée sans empreinte.
    @Test func aModWithoutTranslationFilesIsNeverCached() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("diffcache-vide-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = TranslationDiffCache()
        _ = TranslationCoverage.diffRows(forModAt: root, locale: "fr", cache: cache)
        let dirs = I18nLocaleResolver.i18nDirectories(inModDirectory: root)
        #expect(TranslationStamp.of(directories: dirs) == nil)
        #expect(cache.rows(forModAt: root, stamp: nil) == nil)
    }
}
