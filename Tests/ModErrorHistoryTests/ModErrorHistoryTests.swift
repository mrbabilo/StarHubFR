import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct ModErrorHistoryTests {

    private let day1 = Date(timeIntervalSince1970: 1_000_000)
    private let day2 = Date(timeIntervalSince1970: 2_000_000)

    private func obs(_ mod: String, _ version: String, _ message: String,
                            isError: Bool = true) -> ModErrorHistory.Observation {
        .init(mod: mod, version: version, message: message, isError: isError)
    }

    @Test func recordsCountsPerVersion() {
        var h = ModErrorHistory()
        h.merge([obs("AutoForager", "0.5.3", "boom"),
                 obs("AutoForager", "0.5.3", "bang"),
                 obs("AutoForager", "0.5.3", "careful", isError: false)], at: day1)

        let record = h.history(for: "AutoForager").first
        #expect(record?.version == "0.5.3")
        #expect(record?.errorCount == 2)
        #expect(record?.warningCount == 1)
        #expect(record?.total == 3)
    }

    /// The whole point: comparing a version against the previous one.
    @Test func keepsVersionsApart() {
        var h = ModErrorHistory()
        h.merge([obs("Mod", "1.0", "old bug")], at: day1)
        h.merge([obs("Mod", "2.0", "new bug"), obs("Mod", "2.0", "another")], at: day2)

        let versions = h.history(for: "Mod")
        #expect(versions.count == 2)
        #expect(versions.first?.version == "2.0", "Most recently seen first")
        #expect(versions.first?.errorCount == 2)
        #expect(versions.last?.errorCount == 1)
    }

    @Test func tracksFirstAndLastSeenAcrossMerges() {
        var h = ModErrorHistory()
        h.merge([obs("Mod", "1.0", "x")], at: day2)
        h.merge([obs("Mod", "1.0", "y")], at: day1)   // an older log

        let record = h.history(for: "Mod").first
        #expect(record?.firstSeen == day1, "Earliest observation wins")
        #expect(record?.lastSeen == day2, "Latest observation wins")
    }

    @Test func keepsDistinctSamplesUpToTheCap() {
        var h = ModErrorHistory()
        let many = (1...10).map { obs("Mod", "1.0", "message \($0)") }
        h.merge(many, at: day1)

        let samples = h.history(for: "Mod").first?.samples ?? []
        #expect(samples.count == ModErrorHistory.maxSamples)
        #expect(samples.first == "message 1", "Earliest occurrences are the informative ones")
    }

    @Test func doesNotStoreTheSameMessageTwice() {
        var h = ModErrorHistory()
        h.merge([obs("Mod", "1.0", "same"), obs("Mod", "1.0", "same")], at: day1)

        let record = h.history(for: "Mod").first
        #expect(record?.samples == ["same"], "Samples are distinct")
        #expect(record?.errorCount == 2, "…but every occurrence is still counted")
    }

    @Test func totalsSumEveryVersion() {
        var h = ModErrorHistory()
        h.merge([obs("Mod", "1.0", "a"), obs("Mod", "1.0", "b", isError: false)], at: day1)
        h.merge([obs("Mod", "2.0", "c")], at: day2)

        let totals = h.totals(for: "Mod")
        #expect(totals.errors == 2)
        #expect(totals.warnings == 1)
    }

    @Test func totalsAreZeroForAnUnknownMod() {
        let h = ModErrorHistory()
        let totals = h.totals(for: "Never Seen")
        #expect(totals.errors == 0 && totals.warnings == 0)
        #expect(h.history(for: "Never Seen").isEmpty)
    }

    @Test func pruningDropsOldVersionsButKeepsTheCurrentOne() {
        var h = ModErrorHistory()
        h.merge([obs("Mod", "1.0", "old")], at: day1)
        h.merge([obs("Mod", "2.0", "new")], at: day2)

        h.pruneVersions(for: "Mod", keeping: ["2.0"])
        let versions = h.history(for: "Mod")
        #expect(versions.count == 1)
        #expect(versions.first?.version == "2.0")
    }

    @Test func pruningEverythingForgetsTheMod() {
        var h = ModErrorHistory()
        h.merge([obs("Mod", "1.0", "old")], at: day1)
        h.pruneVersions(for: "Mod", keeping: [])
        #expect(h.mods["Mod"] == nil)
    }

    @Test func removingAModForgetsItsHistory() {
        var h = ModErrorHistory()
        h.merge([obs("Mod", "1.0", "x")], at: day1)
        h.remove(mod: "Mod")
        #expect(h.history(for: "Mod").isEmpty)
    }

    @Test func survivesAJSONRoundTrip() throws {
        var h = ModErrorHistory()
        h.merge([obs("Mod", "1.0", "x"), obs("Mod", "1.0", "y", isError: false)], at: day1)

        let data = try JSONEncoder().encode(h)
        let decoded = try JSONDecoder().decode(ModErrorHistory.self, from: data)
        #expect(decoded == h)
    }

    // MARK: - Store (persistance)

    private var storeDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ModErrorHistoryStoreTests-\(UUID().uuidString)")
    }

    /// Le store rend compte de ses écritures : cette histoire est accumulée et
    /// ne se rebâtit pas (le journal SMAPI suivant écrase le précédent). Un
    /// appelant qui ignore une panne disque croit l'historique sauvegardé — il
    /// découvrira au lancement suivant qu'il ne l'est pas.
    @Test func storeSaveRoundTripsThroughAFile() throws {
        let file = storeDir.appendingPathComponent("mod_error_history.json")
        defer { try? FileManager.default.removeItem(at: storeDir) }

        var history = ModErrorHistory()
        history.merge([obs("Mod", "1.0", "boom")], at: day1)
        #expect(ModErrorHistoryStore.save(history, lastLogDate: day1, to: file))

        let loaded = ModErrorHistoryStore.load(from: file)
        #expect(loaded.history == history)
        #expect(loaded.lastLogDate == day1)
    }

    /// Une écriture impossible rend `false` — la même convention que les
    /// stores voisins (`ModCompatibilityStore`, `InstalledTranslationStore`).
    @Test func storeSaveReportsAFailureWhenItCannotWrite() throws {
        // Un fichier là où le dossier devrait naître : la création échoue,
        // l'écriture avec lui.
        let blocker = storeDir
        defer { try? FileManager.default.removeItem(at: blocker) }
        try Data("pas un dossier".utf8).write(to: blocker)
        let beneath = blocker.appendingPathComponent("mod_error_history.json")

        var history = ModErrorHistory()
        history.merge([obs("Mod", "1.0", "boom")], at: day1)
        #expect(!ModErrorHistoryStore.save(history, lastLogDate: day1, to: beneath))
    }
}
