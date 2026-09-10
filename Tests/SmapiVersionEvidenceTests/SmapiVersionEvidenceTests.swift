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

    // MARK: - Lecture sur disque (`installedVersion`)

    /// L'orchestration qui vivait dans `SmapiInstaller.getInstalledVersion`
    /// : mêmes règles, maintenant testées sur dossiers temporaires — un
    /// « jeu » et un « domicile » fabriqués pour l'essai. Les dates passent
    /// par `setAttributes`, à une heure d'écart : l'égalité stricte des
    /// `Date` après `setAttributes` n'est pas fiable (AGENTS), l'ordre l'est.
    private let fm = FileManager.default

    /// Un « dossier de jeu » avec `smapi-internal/` présent, et le marqueur
    /// de version écrit par l'installateur de l'app.
    private func makeGameDir(markerVersion: String?, modifiedAt: Date? = nil) throws -> String {
        let game = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: game.appendingPathComponent("smapi-internal"),
                               withIntermediateDirectories: true)
        if let markerVersion {
            let marker = game.appendingPathComponent("smapi-internal/.starhubth-installed-version")
            try markerVersion.write(to: marker, atomically: true, encoding: .utf8)
            if let modifiedAt {
                try fm.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: marker.path)
            }
        }
        return game.path
    }

    /// Un « domicile » portant `SMAPI-latest.txt` avec sa bannière.
    private func makeHome(logLine: String?, modifiedAt: Date? = nil) throws -> String {
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let log = home.appendingPathComponent(".config/StardewValley/ErrorLogs/SMAPI-latest.txt")
        try fm.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let logLine {
            try logLine.write(to: log, atomically: true, encoding: .utf8)
            if let modifiedAt {
                try fm.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: log.path)
            }
        }
        return home.path
    }

    private func logLine(_ version: String) -> String {
        "[17:39:40 INFO  SMAPI] SMAPI \(version) with Stardew Valley 1.6.15 on macOS"
    }

    /// X77 : sans `smapi-internal/`, SMAPI est absent — même si un journal
    /// valide traîne (une désinstallation laisse le journal derrière elle).
    @Test func withoutTheMarkerFolderNothingIsRead() throws {
        let game = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let home = try makeHome(logLine: logLine("4.5.2"))
        #expect(SmapiVersionEvidence.installedVersion(gameDir: game, home: home) == nil)
    }

    @Test func theMarkerAloneAnswersFromDisk() throws {
        let game = try makeGameDir(markerVersion: "4.5.2")
        #expect(SmapiVersionEvidence.installedVersion(gameDir: game, home: "/nulle-part") == "4.5.2")
    }

    /// X31 sur disque : SMAPI mis à jour par son propre installateur, le
    /// marqueur de l'app traîne — le journal, plus récent, dit la version
    /// réellement chargée.
    @Test func aNewerLogOnDiskOverridesTheMarker() throws {
        let markerDate = Date(timeIntervalSinceNow: -3_600)
        let logDate = Date()
        let game = try makeGameDir(markerVersion: "4.4.0", modifiedAt: markerDate)
        let home = try makeHome(logLine: logLine("4.5.2"), modifiedAt: logDate)
        #expect(SmapiVersionEvidence.installedVersion(gameDir: game, home: home) == "4.5.2")
    }

    @Test func aNewerMarkerOverridesTheLog() throws {
        let logDate = Date(timeIntervalSinceNow: -3_600)
        let markerDate = Date()
        let game = try makeGameDir(markerVersion: "4.5.2", modifiedAt: markerDate)
        let home = try makeHome(logLine: logLine("4.4.0"), modifiedAt: logDate)
        #expect(SmapiVersionEvidence.installedVersion(gameDir: game, home: home) == "4.5.2")
    }

    /// Présent, mais ni le marqueur ni le journal ne nomment de version :
    /// « Installed » — l'app le sait là, pas quelle version.
    @Test func anInstalledButUnversionedSMAPIIsReportedAsInstalled() throws {
        let game = try makeGameDir(markerVersion: nil)
        #expect(SmapiVersionEvidence.installedVersion(gameDir: game, home: "/nulle-part") == "Installed")
    }

    /// Un marqueur interrompu (blanc) ne doit pas faire taire le journal —
    /// la règle `trimmed`, vérifiée sur le chemin disque.
    @Test func aBlankMarkerFileDoesNotSilenceTheLog() throws {
        let game = try makeGameDir(markerVersion: "   \n")
        let home = try makeHome(logLine: logLine("4.5.2"))
        #expect(SmapiVersionEvidence.installedVersion(gameDir: game, home: home) == "4.5.2")
    }
}
