import Testing
import Foundation
@testable import StarHubTHCore

/// Les deux décisions que prend un rechargement du journal SMAPI, hors de
/// l'orchestration qui les portait : **quelles alertes journaliser** (sans
/// réécrire la même liste à chaque relecture) et **si ce journal doit être
/// replié** dans l'historique d'erreurs par mod.
///
/// Les deux sont de l'état qui s'accumule d'une exécution à l'autre — le
/// profil de défaut le plus cher du dépôt, et aucune des deux n'était testée.
@Suite struct SmapiHealthFoldTests {

    private func entry(_ message: String, _ level: LogLevel,
                       mod: String? = nil) -> LogEntry {
        LogEntry(timestamp: "00:00:00", message: message, level: level,
                 source: .smapi, modName: mod)
    }

    // MARK: - Quelles alertes journaliser

    @Test func everyAlertIsLoggedTheFirstTime() {
        let out = SmapiHealthFold.alertsToLog(current: ["a", "b"], alreadyLogged: [])
        #expect(out.toLog == ["a", "b"])
        #expect(out.updatedSet == ["a", "b"])
    }

    @Test func analertAlreadyLoggedIsNotLoggedAgain() {
        let out = SmapiHealthFold.alertsToLog(current: ["a", "b"], alreadyLogged: ["a", "b"])
        #expect(out.toLog.isEmpty)
        // Rien de neuf : le jeu de référence n'est pas réécrit.
        #expect(out.updatedSet == nil)
    }

    @Test func aReplacedAlertIsCaughtBecauseTheDiffIsByContent() {
        // Le compte ne bouge pas — un diff par compte aurait tout raté.
        let out = SmapiHealthFold.alertsToLog(current: ["a", "c"], alreadyLogged: ["a", "b"])
        #expect(out.toLog == ["c"])
        #expect(out.updatedSet == ["a", "c"])
    }

    /// ⚠️ Comportement **conservé tel quel**, pas dérivé d'un raisonnement :
    /// quand rien n'est neuf, le jeu de référence reste celui d'avant. Une
    /// alerte qui disparaît puis revient ne sera donc pas re-journalisée.
    /// Ce test dit ce que le code fait, pas qu'il a raison.
    @Test func aShrinkingListLeavesTheReferenceSetUntouched() {
        let out = SmapiHealthFold.alertsToLog(current: ["a"], alreadyLogged: ["a", "b"])
        #expect(out.toLog.isEmpty)
        #expect(out.updatedSet == nil)
    }

    @Test func alertsAreLoggedInTheOrderTheyWereParsed_notSetOrder() {
        // Un `Set` n'a pas d'ordre : parcourir les alertes neuves directement
        // rendrait le journal non déterministe d'un lancement à l'autre
        // (Swift randomise le hachage par processus).
        //
        // ⚠️ Huit éléments, et pas trois : à trois, le sabotage `Array(fresh)`
        // est passé — l'ordre du `Set` avait coïncidé. Le test est
        // probabiliste **contre un sabotage** (1 chance sur 8! qu'un ordre
        // arbitraire tombe juste), jamais contre du code correct : celui-ci
        // rend toujours l'ordre de `current`.
        let parsed = ["zeta", "mu", "alpha", "omega", "beta", "tau", "iota", "rho"]
        let out = SmapiHealthFold.alertsToLog(current: parsed, alreadyLogged: [])
        #expect(out.toLog == parsed)
    }

    // MARK: - Faut-il replier ce journal dans l'historique ?

    @Test func aLogWithNoDateIsNeverFolded() {
        // Sans date, rien ne distingue une relecture d'un nouveau journal :
        // replier compterait deux fois les mêmes erreurs.
        #expect(SmapiHealthFold.shouldFold(logDate: nil, lastFolded: nil) == false)
    }

    @Test func aFirstDatedLogIsFolded() {
        #expect(SmapiHealthFold.shouldFold(logDate: Date(timeIntervalSince1970: 10),
                                           lastFolded: nil) == true)
    }

    @Test func theSameLogIsNotFoldedTwice() {
        let d = Date(timeIntervalSince1970: 10)
        #expect(SmapiHealthFold.shouldFold(logDate: d, lastFolded: d) == false)
    }

    @Test func anOlderLogIsNotFolded() {
        // Le jeu a été relancé sur une sauvegarde antérieure, ou l'horloge a
        // reculé : on n'inverse pas l'historique.
        #expect(SmapiHealthFold.shouldFold(logDate: Date(timeIntervalSince1970: 5),
                                           lastFolded: Date(timeIntervalSince1970: 10)) == false)
    }

    @Test func aNewerLogIsFolded() {
        #expect(SmapiHealthFold.shouldFold(logDate: Date(timeIntervalSince1970: 20),
                                           lastFolded: Date(timeIntervalSince1970: 10)) == true)
    }

    // MARK: - Ce qu'on retient d'un journal

    @Test func onlyErrorsAndWarningsAttributedToAnInstalledModAreKept() {
        let entries = [
            entry("boum", .error, mod: "Alpha"),
            entry("attention", .warning, mod: "Alpha"),
            entry("info", .info, mod: "Alpha"),          // pas une alerte
            entry("trace", .trace, mod: "Alpha"),        // pas une alerte
            entry("orphelin", .error, mod: "Inconnu"),   // pas au parc
            entry("sans imputation", .error)             // aucun mod nommé
        ]
        let obs = SmapiHealthFold.observations(from: entries) { name in
            name == "Alpha" ? .init(folderName: "AlphaDir", version: "1.2") : nil
        }
        #expect(obs.map(\.message) == ["boum", "attention"])
        #expect(obs.map(\.isError) == [true, false])
        #expect(obs.allSatisfy { $0.mod == "AlphaDir" && $0.version == "1.2" })
    }

    @Test func aLogWithNothingToRecordYieldsNoObservation() {
        let obs = SmapiHealthFold.observations(from: [entry("info", .info, mod: "Alpha")]) { _ in
            .init(folderName: "AlphaDir", version: "1.2")
        }
        #expect(obs.isEmpty)
    }
}
