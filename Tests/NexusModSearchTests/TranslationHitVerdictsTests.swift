import Foundation
import Testing
@testable import StarHubTHCore

/// P5-4 — un faux résultat écarté ne revient pas, et se rétablit.
struct TranslationHitVerdictsTests {
    private func hit(_ id: Int, _ name: String = "Trad") -> NexusModSearch.Hit {
        NexusModSearch.Hit(modId: id, name: name, version: "1.0", updatedAt: nil,
                           categoryName: "", uploader: "u", adultContent: false)
    }

    /// X148 — l'écart suit le dossier renommé : le faux résultat ne revient pas.
    @Test func aDismissalFollowsARenamedFolder() {
        var verdicts = TranslationHitVerdicts()
        verdicts.dismiss(hit(1), for: "Old", modName: "Mod", at: .now)
        verdicts.dismiss(hit(2), for: "Neighbour", modName: "Autre", at: .now)

        let changed = verdicts.migrate(from: "Old", to: "New", shared: false)

        #expect(changed)
        #expect(verdicts.dismissedModIds(for: "New") == [1])
        #expect(verdicts.dismissedModIds(for: "Old").isEmpty)
        #expect(verdicts.dismissedModIds(for: "Neighbour") == [2])
    }

    /// Une préférence : en collision, les deux mods la gardent.
    @Test func aDismissalIsCopiedOnASharedName() {
        var verdicts = TranslationHitVerdicts()
        verdicts.dismiss(hit(1), for: "Old", modName: "Mod", at: .now)

        verdicts.migrate(from: "Old", to: "New", shared: true)

        #expect(verdicts.dismissedModIds(for: "New") == [1])
        #expect(verdicts.dismissedModIds(for: "Old") == [1])
    }

    /// Un écart déjà posé sous le nouveau nom (mod désinstallé) n'est pas doublé.
    @Test func aMigrationDoesNotDoubleAnExistingDismissal() {
        var verdicts = TranslationHitVerdicts()
        verdicts.dismiss(hit(1), for: "Old", modName: "Mod", at: .now)
        verdicts.dismiss(hit(1), for: "New", modName: "Mod", at: .now)

        verdicts.migrate(from: "Old", to: "New", shared: false)

        #expect(verdicts.dismissals.count == 1)
    }

    @Test func aDismissalIsPerModAndPerHit() {
        var verdicts = TranslationHitVerdicts()
        verdicts.dismiss(hit(1), for: "Swim", modName: "Swim Mod", at: .now)
        #expect(verdicts.dismissedModIds(for: "Swim") == [1])
        #expect(verdicts.dismissedModIds(for: "Tea").isEmpty)
    }

    /// Écarter deux fois ne double pas la ligne « Écartés ».
    @Test func dismissingTwiceKeepsOneRowAndRestoreRemovesIt() {
        var verdicts = TranslationHitVerdicts()
        verdicts.dismiss(hit(1), for: "Swim", modName: "Swim Mod", at: .now)
        verdicts.dismiss(hit(1), for: "Swim", modName: "Swim Mod", at: .now)
        #expect(verdicts.dismissals.count == 1)
        verdicts.restore(verdicts.dismissals[0])
        #expect(verdicts.dismissals.isEmpty)
    }

    /// Le filtre se lit au statut : l'entrée brute garde le résultat, celle
    /// qu'on montre ne l'a plus, et un mod sans autre résultat passe à
    /// « Rien trouvé ».
    @Test func theStatusDropsDismissedHitsButTheCacheKeepsThem() {
        let entry = FrenchTranslationSweep.Entry(hits: [hit(1), hit(2)], searchedAt: .now)
        #expect(FrenchTranslationSweep.status(entry: entry.excluding([1]), installed: nil) == .available([hit(2)]))
        #expect(FrenchTranslationSweep.status(entry: entry.excluding([1, 2]), installed: nil) == .nothingFound)
        #expect(entry.hits.count == 2)
    }

    /// Une panne reste une panne, même tous résultats écartés.
    @Test func aFailedSearchStaysFailed() {
        let failed = FrenchTranslationSweep.Entry(hits: [hit(1)], searchedAt: .now, failed: true)
        #expect(FrenchTranslationSweep.status(entry: failed.excluding([1]), installed: nil) == .failed)
    }

    @Test func dismissalsSurviveARoundTripOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranslationHitVerdictsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("verdicts.json")
        var verdicts = TranslationHitVerdicts()
        verdicts.dismiss(hit(7, "Modern Bathroom"), for: "Swim", modName: "Swim Mod", at: Date(timeIntervalSince1970: 0))
        #expect(TranslationHitVerdicts.Storage.save(verdicts, to: url))
        #expect(TranslationHitVerdicts.Storage.load(from: url) == verdicts)
        #expect(TranslationHitVerdicts.Storage.load(from: dir.appendingPathComponent("absent.json")).dismissals.isEmpty)
    }
}
