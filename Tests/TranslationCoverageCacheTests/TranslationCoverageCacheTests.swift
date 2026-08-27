import Foundation
import Testing
@testable import StarHubTHCore

/// Un dossier de mod jetable.
private struct Fixture {
    let root: URL
    init(_ files: [String: String]) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("covcache-\(UUID().uuidString)", isDirectory: true)
        for (relative, content) in files {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    var i18nDirectories: [URL] {
        I18nLocaleResolver.i18nDirectories(inModDirectory: root, stoppingAtNestedMods: true)
    }
    func write(_ relative: String, _ content: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
    }
    func touch(_ relative: String, secondsFromNow: TimeInterval) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(secondsFromNow)],
            ofItemAtPath: url.path)
    }
}

@Suite struct TranslationStampTests {

    /// Rien à empreindre, rien à mettre en cache : une empreinte vide vaudrait
    /// pour n'importe quel autre mod sans traduction.
    @Test func aModWithoutTranslationFilesHasNoStamp() throws {
        let mod = try Fixture(["manifest.json": "{}"])
        defer { mod.cleanup() }
        #expect(TranslationStamp.of(directories: mod.i18nDirectories) == nil)
    }

    @Test func theSameFilesGiveTheSameStamp() throws {
        let mod = try Fixture(["i18n/default.json": #"{"a": "1"}"#])
        defer { mod.cleanup() }
        let first = TranslationStamp.of(directories: mod.i18nDirectories)
        let second = TranslationStamp.of(directories: mod.i18nDirectories)
        #expect(first != nil)
        #expect(first == second)
    }

    // MARK: - Ce qui doit invalider

    /// Le cas courant : la traduction avance, le fichier grossit.
    @Test func aChangedFileSizeChangesTheStamp() throws {
        let mod = try Fixture(["i18n/default.json": #"{"a": "1"}"#,
                               "i18n/fr.json": #"{}"#])
        defer { mod.cleanup() }
        let before = TranslationStamp.of(directories: mod.i18nDirectories)
        try mod.write("i18n/fr.json", #"{"a": "un"}"#)
        #expect(TranslationStamp.of(directories: mod.i18nDirectories) != before)
    }

    /// Le cas retors : traduire sans changer la taille. `"Yes"` → `"Oui"` fait
    /// exactement le même nombre d'octets — la taille seule ne suffirait pas,
    /// et un cache validé sur elle seule servirait un chiffre périmé.
    @Test func aSameSizeEditStillChangesTheStamp() throws {
        let mod = try Fixture(["i18n/default.json": #"{"a": "Yes"}"#,
                               "i18n/fr.json": #"{"a": "Yes"}"#])
        defer { mod.cleanup() }
        let before = try #require(TranslationStamp.of(directories: mod.i18nDirectories))
        try mod.write("i18n/fr.json", #"{"a": "Oui"}"#)
        try mod.touch("i18n/fr.json", secondsFromNow: 120)
        let after = try #require(TranslationStamp.of(directories: mod.i18nDirectories))
        #expect(after.totalSize == before.totalSize)
        #expect(after != before)
    }

    /// Une locale ajoutée est un fichier de plus.
    @Test func anAddedFileChangesTheStamp() throws {
        let mod = try Fixture(["i18n/default.json": #"{"a": "1"}"#])
        defer { mod.cleanup() }
        let before = TranslationStamp.of(directories: mod.i18nDirectories)
        try mod.write("i18n/fr.json", #"{"a": "un"}"#)
        #expect(TranslationStamp.of(directories: mod.i18nDirectories) != before)
    }

    /// Layout B — `i18n/fr/dialogue.json` : un mod qui range ses traductions
    /// en sous-dossiers doit être empreint comme les autres, sans quoi son
    /// travail ne serait jamais revu.
    @Test func layoutBFilesAreStampedToo() throws {
        let mod = try Fixture(["i18n/default/a.json": #"{"a": "1"}"#])
        defer { mod.cleanup() }
        let before = try #require(TranslationStamp.of(directories: mod.i18nDirectories))
        #expect(before.fileCount == 1)
        try mod.write("i18n/fr/a.json", #"{"a": "un"}"#)
        let after = try #require(TranslationStamp.of(directories: mod.i18nDirectories))
        #expect(after.fileCount == 2)
        #expect(after != before)
    }

    /// Les traductions d'un mod **imbriqué** ne sont pas les siennes : elles
    /// sont empreintes pour son propre compte, comme elles sont mesurées.
    @Test func aNestedModDoesNotContributeToItsHostStamp() throws {
        let mod = try Fixture([
            "manifest.json": #"{"UniqueID": "hote"}"#,
            "i18n/default.json": #"{"a": "1"}"#,
            "Imbrique/manifest.json": #"{"UniqueID": "imbrique"}"#,
            "Imbrique/i18n/default.json": #"{"b": "2"}"#,
        ])
        defer { mod.cleanup() }
        let stamp = try #require(TranslationStamp.of(directories: mod.i18nDirectories))
        #expect(stamp.fileCount == 1)
    }
}

@Suite struct TranslationCoverageCacheTests {

    private func entry(total: Int, translated: Int, stamp: TranslationStamp) -> TranslationCoverageCache.Entry {
        TranslationCoverageCache.Entry(stamp: stamp, total: total, translated: translated)
    }
    private let stampA = TranslationStamp(fileCount: 2, totalSize: 100, newestModified: 1_700_000_000)
    private let stampB = TranslationStamp(fileCount: 2, totalSize: 100, newestModified: 1_700_000_060)

    // MARK: - Validité

    @Test func anUnchangedStampKeepsTheEntry() {
        let cached = entry(total: 10, translated: 4, stamp: stampA)
        #expect(TranslationCoverageCache.valid(cached, against: stampA)?.translated == 4)
    }

    @Test func aChangedStampDropsTheEntry() {
        let cached = entry(total: 10, translated: 4, stamp: stampA)
        #expect(TranslationCoverageCache.valid(cached, against: stampB) == nil)
    }

    /// Plus de fichiers du tout : le mod a perdu ses traductions, la mesure
    /// gardée ne veut plus rien dire.
    @Test func aMissingStampDropsTheEntry() {
        let cached = entry(total: 10, translated: 4, stamp: stampA)
        #expect(TranslationCoverageCache.valid(cached, against: nil) == nil)
    }

    @Test func anAbsentEntryIsNeverValid() {
        #expect(TranslationCoverageCache.valid(nil, against: stampA) == nil)
    }

    // MARK: - Le fichier

    @Test func entriesSurviveARoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let entries = ["auteur.mod": entry(total: 292, translated: 0, stamp: stampA)]
        TranslationCoverageCache.save(entries, to: url)
        #expect(TranslationCoverageCache.load(from: url) == entries)
    }

    /// Un fichier absent ou illisible ne fait perdre qu'une mesure : le pire
    /// qui puisse arriver est de tout remesurer, jamais d'afficher un chiffre
    /// faux.
    @Test func anUnreadableFileGivesAnEmptyCache() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache-\(UUID().uuidString).json")
        #expect(TranslationCoverageCache.load(from: url).isEmpty)

        try Data("pas du json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(TranslationCoverageCache.load(from: url).isEmpty)
    }

    /// Sans nettoyage, le fichier ne ferait que grossir : chaque mod
    /// désinstallé y laisserait son empreinte pour toujours.
    @Test func uninstalledModsArePruned() {
        let entries = ["a.mod": entry(total: 1, translated: 1, stamp: stampA),
                       "b.mod": entry(total: 2, translated: 0, stamp: stampA)]
        let kept = TranslationCoverageCache.pruned(entries, keeping: ["A.Mod"])
        #expect(Set(kept.keys) == ["a.mod"])
    }
}

/// Le parcours des dossiers coûte 2,5 s sur le parc réel : l'appelant qui les
/// a déjà repérés — pour l'empreinte — ne doit pas le repayer. Les deux voies
/// doivent donc rendre exactement la même chose.
@Suite struct CoverageFromKnownDirectoriesTests {

    @Test func measuringFromKnownDirectoriesMatchesTheFullWalk() throws {
        let mod = try Fixture([
            "manifest.json": #"{"UniqueID": "hote"}"#,
            "i18n/default.json": #"{"a": "1", "b": "2"}"#,
            "i18n/fr.json": #"{"a": "un"}"#,
            "Imbrique/manifest.json": #"{"UniqueID": "imbrique"}"#,
            "Imbrique/i18n/default.json": #"{"c": "3"}"#,
        ])
        defer { mod.cleanup() }

        let walked = try #require(TranslationCoverage.coverage(forModAt: mod.root, locale: "fr",
                                                               ownDirectoriesOnly: true))
        let direct = try #require(TranslationCoverage.coverage(inDirectories: mod.i18nDirectories,
                                                               locale: "fr"))
        #expect(walked == direct)
        #expect(direct.total == 2)
        #expect(direct.translated == 1)
    }

    @Test func noDirectoriesMeansNothingToMeasure() {
        #expect(TranslationCoverage.coverage(inDirectories: [], locale: "fr") == nil)
    }
}
