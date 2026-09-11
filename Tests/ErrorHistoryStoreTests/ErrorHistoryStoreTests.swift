import Testing
import Foundation
@testable import StarHubTHCore

/// L'historique d'erreurs par mod et par version : ce qu'un journal y ajoute,
/// et ce qui a le droit d'y toucher.
///
/// La règle centrale est une **garde contre une perte de données** : tant que
/// l'historique n'a pas été chargé du disque, rien ne doit le muter — le
/// muter reviendrait à écrire un historique vide par-dessus le fichier. Elle
/// vivait au ViewModel sous la forme de deux `if errorHistoryLoaded` qu'un
/// troisième appelant aurait pu oublier.
///
/// Les I/O arrivent par closures : aucun test n'écrit dans le vrai
/// Application Support.
@Suite struct ErrorHistoryStoreTests {

    private func observation(_ mod: String, isError: Bool = true) -> ModErrorHistory.Observation {
        .init(mod: mod, version: "1.0", message: "boum", isError: isError)
    }

    /// Un store branché sur un disque de mensonge : on voit ce qu'il lit et
    /// ce qu'il écrit, sans toucher au vrai fichier.
    private final class FakeDisk {
        var stored: (history: ModErrorHistory, lastLogDate: Date?) = (ModErrorHistory(), nil)
        private(set) var saveCount = 0
        var saveSucceeds = true

        func load() -> (history: ModErrorHistory, lastLogDate: Date?) { stored }
        func save(_ h: ModErrorHistory, _ d: Date?) -> Bool {
            saveCount += 1
            guard saveSucceeds else { return false }
            stored = (h, d)
            return true
        }
    }

    private func store(_ disk: FakeDisk) -> ErrorHistoryStore {
        ErrorHistoryStore(load: disk.load, save: disk.save)
    }

    // MARK: - La garde : rien ne bouge avant le chargement

    @Test func foldingBeforeLoadingDoesNothing() {
        let disk = FakeDisk()
        let s = store(disk)
        s.fold([observation("Alpha")], at: Date(timeIntervalSince1970: 10))
        #expect(s.history.history(for: "Alpha").isEmpty)
        #expect(disk.saveCount == 0)
    }

    @Test func renamingBeforeLoadingDoesNothing() {
        let disk = FakeDisk()
        let s = store(disk)
        s.rename(from: "Alpha", to: "Beta", shared: false)
        #expect(disk.saveCount == 0)
    }

    @Test func forgettingBeforeLoadingDoesNothing() {
        let disk = FakeDisk()
        let s = store(disk)
        s.forget(mod: "Alpha")
        #expect(disk.saveCount == 0)
    }

    // MARK: - Le chargement

    @Test func loadingHappensOnceAndBringsBackWhatWasStored() {
        let disk = FakeDisk()
        var seeded = ModErrorHistory()
        seeded.merge([observation("Alpha")], at: Date(timeIntervalSince1970: 5))
        disk.stored = (seeded, Date(timeIntervalSince1970: 5))

        let s = store(disk)
        s.loadIfNeeded()
        #expect(s.history.history(for: "Alpha").count == 1)
        #expect(s.lastFoldedDate == Date(timeIntervalSince1970: 5))

        // Un second appel ne relit pas : l'historique en mémoire fait foi,
        // et le relire écraserait ce qui n'a pas encore été persisté.
        disk.stored = (ModErrorHistory(), nil)
        s.loadIfNeeded()
        #expect(s.history.history(for: "Alpha").count == 1)
    }

    // MARK: - Le repli d'un journal

    @Test func foldingRecordsTheObservationsAndAdvancesTheDate() {
        let disk = FakeDisk()
        let s = store(disk)
        s.loadIfNeeded()
        let when = Date(timeIntervalSince1970: 10)
        s.fold([observation("Alpha")], at: when)
        #expect(s.history.history(for: "Alpha").count == 1)
        #expect(s.lastFoldedDate == when)
        #expect(disk.saveCount == 1)
    }

    /// Un journal sans erreur imputable avance quand même la date : sans ça,
    /// il serait relu et réexaminé à chaque ouverture d'onglet.
    @Test func aLogWithNoObservationStillAdvancesTheDateAndPersists() {
        let disk = FakeDisk()
        let s = store(disk)
        s.loadIfNeeded()
        let when = Date(timeIntervalSince1970: 10)
        s.fold([], at: when)
        #expect(s.lastFoldedDate == when)
        #expect(disk.saveCount == 1)
    }

    // MARK: - Renommer, oublier

    @Test func renamingMovesAModsRecordsUnderItsNewFolder() {
        let disk = FakeDisk()
        let s = store(disk)
        s.loadIfNeeded()
        s.fold([observation("Alpha")], at: Date(timeIntervalSince1970: 10))
        s.rename(from: "Alpha", to: "Beta", shared: false)
        #expect(s.history.history(for: "Beta").count == 1)
        #expect(s.history.history(for: "Alpha").isEmpty)
    }

    @Test func renamingAModWithNoHistoryWritesNothing() {
        let disk = FakeDisk()
        let s = store(disk)
        s.loadIfNeeded()
        let before = disk.saveCount
        s.rename(from: "Inconnu", to: "Autre", shared: false)
        #expect(disk.saveCount == before)
    }

    /// Un mod jeté à la corbeille n'a plus à peser sur le fichier — sinon il
    /// grossit indéfiniment avec des mods désinstallés.
    @Test func forgettingAModDropsItsRecordsAndPersists() {
        let disk = FakeDisk()
        let s = store(disk)
        s.loadIfNeeded()
        s.fold([observation("Alpha")], at: Date(timeIntervalSince1970: 10))
        let before = disk.saveCount
        s.forget(mod: "Alpha")
        #expect(s.history.history(for: "Alpha").isEmpty)
        #expect(disk.saveCount == before + 1)
    }

    // MARK: - Quand l'écriture échoue

    /// L'historique s'accumule et ne se rebâtit pas : le journal SMAPI suivant
    /// écrase le précédent. Une panne d'écriture doit se dire, sinon elle ne
    /// se verrait qu'au lancement suivant — et par une perte.
    @Test func aFailedWriteIsReported() {
        let disk = FakeDisk()
        disk.saveSucceeds = false
        var reported = 0
        let s = ErrorHistoryStore(load: disk.load, save: disk.save,
                                  onWriteFailure: { reported += 1 })
        s.loadIfNeeded()
        s.fold([observation("Alpha")], at: Date(timeIntervalSince1970: 10))
        #expect(reported == 1)
    }

    @Test func aSuccessfulWriteIsSilent() {
        let disk = FakeDisk()
        var reported = 0
        let s = ErrorHistoryStore(load: disk.load, save: disk.save,
                                  onWriteFailure: { reported += 1 })
        s.loadIfNeeded()
        s.fold([observation("Alpha")], at: Date(timeIntervalSince1970: 10))
        #expect(reported == 0)
    }
}
