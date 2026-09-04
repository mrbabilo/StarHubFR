import Foundation
import Testing
@testable import StarHubTHCore

private func date(_ iso: String) -> Date {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: iso)!
}

@Suite struct SmapiVersionEvidenceTests {

    /// Rien à lire : l'app sait que SMAPI est là (le lanceur d'origine a été
    /// déplacé), pas quelle version. Rendre `nil` laisse l'appelant le dire.
    @Test func withoutAnyStatementNothingIsClaimed() {
        #expect(SmapiVersionEvidence.resolve(marker: nil, log: nil) == nil)
    }

    /// Une installation faite par l'app, jeu jamais lancé depuis : le marqueur
    /// est la seule source.
    @Test func theMarkerAloneAnswers() {
        let marker = SmapiVersionEvidence.Statement(version: "4.5.2",
                                                    observedAt: date("2026-07-23 19:50"))
        #expect(SmapiVersionEvidence.resolve(marker: marker, log: nil) == "4.5.2")
    }

    /// Une installation faite ailleurs (installateur officiel), jamais par
    /// l'app : le journal est la seule source.
    @Test func theLogAloneAnswers() {
        let log = SmapiVersionEvidence.Statement(version: "4.5.2",
                                                 observedAt: date("2026-09-01 17:44"))
        #expect(SmapiVersionEvidence.resolve(marker: nil, log: log) == "4.5.2")
    }

    /// **Le cas de X31.** SMAPI mis à jour par son propre installateur : il ne
    /// réécrit pas notre marqueur. Le jeu a tourné depuis, et son journal dit
    /// la version réellement chargée. C'est lui qui a raison.
    @Test func aLogWrittenAfterTheMarkerWins() {
        let marker = SmapiVersionEvidence.Statement(version: "4.4.0",
                                                    observedAt: date("2026-07-23 19:50"))
        let log = SmapiVersionEvidence.Statement(version: "4.5.2",
                                                 observedAt: date("2026-09-01 17:44"))
        #expect(SmapiVersionEvidence.resolve(marker: marker, log: log) == "4.5.2")
    }

    /// Le sens inverse compte autant : l'app vient d'installer, le jeu n'a pas
    /// été relancé. Le journal parle encore de la version d'avant — croire la
    /// plus récente **des deux dates**, pas le journal par principe.
    @Test func aMarkerWrittenAfterTheLogWins() {
        let log = SmapiVersionEvidence.Statement(version: "4.4.0",
                                                 observedAt: date("2026-09-01 17:44"))
        let marker = SmapiVersionEvidence.Statement(version: "4.5.2",
                                                    observedAt: date("2026-09-02 10:00"))
        #expect(SmapiVersionEvidence.resolve(marker: marker, log: log) == "4.5.2")
    }

    /// À date égale — le jeu relancé dans la minute de l'installation — le
    /// marqueur l'emporte : il dit ce qui a été **installé**, quand le journal
    /// dit ce qui a été **chargé**, et une seconde d'écart de granularité ne
    /// doit pas faire préférer l'un à l'autre au hasard.
    @Test func theMarkerBreaksATie() {
        let when = date("2026-09-02 10:00")
        let marker = SmapiVersionEvidence.Statement(version: "4.5.2", observedAt: when)
        let log = SmapiVersionEvidence.Statement(version: "4.4.0", observedAt: when)
        #expect(SmapiVersionEvidence.resolve(marker: marker, log: log) == "4.5.2")
    }

    /// Un marqueur vide (écriture interrompue) n'est pas une affirmation : il
    /// ne doit pas faire taire le journal.
    @Test func aBlankStatementIsNotAStatement() {
        let marker = SmapiVersionEvidence.Statement(version: "   ",
                                                    observedAt: date("2026-09-02 10:00"))
        let log = SmapiVersionEvidence.Statement(version: "4.5.2",
                                                 observedAt: date("2026-09-01 17:44"))
        #expect(SmapiVersionEvidence.resolve(marker: marker, log: log) == "4.5.2")
    }

    /// Deux sources vides ne font pas une version.
    @Test func twoBlankStatementsClaimNothing() {
        let when = date("2026-09-02 10:00")
        #expect(SmapiVersionEvidence.resolve(
            marker: SmapiVersionEvidence.Statement(version: "", observedAt: when),
            log: SmapiVersionEvidence.Statement(version: "\n", observedAt: when)) == nil)
    }

    /// La version rendue est débarrassée de ses blancs : le marqueur est écrit
    /// par `write(toFile:)` et relu tel quel, retour à la ligne compris.
    @Test func theAnsweredVersionIsTrimmed() {
        let marker = SmapiVersionEvidence.Statement(version: " 4.5.2\n",
                                                    observedAt: date("2026-09-02 10:00"))
        #expect(SmapiVersionEvidence.resolve(marker: marker, log: nil) == "4.5.2")
    }

    // MARK: - Lecture de la ligne de journal

    /// La première ligne du journal de SMAPI, telle qu'elle est sur la machine
    /// de référence.
    @Test func theVersionIsReadFromTheFirstLogLine() {
        let line = "[17:39:40 INFO  SMAPI] SMAPI 4.5.2 with Stardew Valley 1.6.15 build 24356 on macOS Unix 26.6.2"
        #expect(SmapiVersionEvidence.version(inLogLine: line) == "4.5.2")
    }

    /// Une ligne qui ne nomme pas SMAPI ne donne pas de version — plutôt que
    /// d'attraper le premier nombre qui passe.
    @Test func aLineWithoutTheSmapiBannerGivesNothing() {
        #expect(SmapiVersionEvidence.version(inLogLine: "[17:39:40 INFO  SMAPI] Mods go here: /Applications") == nil)
    }

    /// Une version à quatre segments (SMAPI en publie : 4.0.0.1) n'est pas
    /// tronquée à trois.
    @Test func aFourSegmentVersionIsKeptWhole() {
        let line = "[17:39:40 INFO  SMAPI] SMAPI 4.0.0.1 with Stardew Valley 1.6.15"
        #expect(SmapiVersionEvidence.version(inLogLine: line) == "4.0.0.1")
    }

    /// Une pré-version (`4.6.0-beta.3`) est rendue entière : la tronquer ferait
    /// croire à une version stable déjà sortie.
    @Test func aPrereleaseIsKeptWhole() {
        let line = "[17:39:40 INFO  SMAPI] SMAPI 4.6.0-beta.3 with Stardew Valley 1.6.15"
        #expect(SmapiVersionEvidence.version(inLogLine: line) == "4.6.0-beta.3")
    }
}
