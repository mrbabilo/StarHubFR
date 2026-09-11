import Testing
import Foundation
@testable import StarHubTHCore

/// La fenêtre mémoire du journal : qui reste quand le plafond est atteint.
///
/// Le *quoi jeter* est prouvé ailleurs (`LogNoiseTests` — le bruit `TRACE`
/// part avant le signal). Ici c'est la **composition**, et elle porte deux
/// bugs réels : un rechargement qui empilait une copie entière du journal
/// SMAPI, et un écrêtage par la tête qui effaçait tout le journal de l'app.
@Suite struct LogBudgetTests {

    private func entry(_ message: String, _ level: LogLevel = .info,
                       _ source: LogSource = .app) -> LogEntry {
        LogEntry(timestamp: "00:00:00", message: message, level: level, source: source)
    }

    // MARK: - Un rechargement remplace, il n'empile pas

    @Test func reloadingDropsThePreviousSmapiBlock() {
        let existing = [entry("app"), entry("vieux", .info, .smapi)]
        let out = LogBudget.replacingSmapi(in: existing,
                                           with: [entry("neuf", .info, .smapi)], cap: 100)
        #expect(out.map(\.message) == ["app", "neuf"])
    }

    @Test func reloadingKeepsEveryAppEntry() {
        let existing = [entry("a1"), entry("a2"), entry("vieux", .info, .smapi)]
        let out = LogBudget.replacingSmapi(in: existing, with: [], cap: 100)
        #expect(out.map(\.message) == ["a1", "a2"])
    }

    // MARK: - Le budget se compte sur ce qui reste

    @Test func theSmapiBlockIsBudgetedOnWhatTheAppEntriesLeave() {
        // Plafond 5, trois entrées d'app : il reste deux places pour SMAPI.
        let existing = (1...3).map { entry("a\($0)") }
        let incoming = (1...10).map { entry("s\($0)", .trace, .smapi) }
        let out = LogBudget.replacingSmapi(in: existing, with: incoming, cap: 5)
        #expect(out.count == 5)
        #expect(out.filter { $0.source == .app }.count == 3)
    }

    @Test func appEntriesSurviveAnOversizedSmapiLog() {
        // Le défaut historique : un écrêtage par la tête du tableau combiné
        // effaçait les entrées de l'app, qui vivent en tête.
        let existing = (1...3).map { entry("a\($0)") }
        let incoming = (1...500).map { entry("s\($0)", .trace, .smapi) }
        let out = LogBudget.replacingSmapi(in: existing, with: incoming, cap: 4)
        #expect(out.filter { $0.source == .app }.map(\.message) == ["a1", "a2", "a3"])
    }

    @Test func aFullAppLogLeavesNoRoomAndThatIsNotACrash() {
        let existing = (1...6).map { entry("a\($0)") }
        let out = LogBudget.replacingSmapi(in: existing,
                                           with: [entry("s", .info, .smapi)], cap: 4)
        #expect(out.allSatisfy { $0.source == .app })
    }

    // MARK: - Le signal survit au bruit

    @Test func trimmingShedsTraceBeforeTheStartupDiagnostic() {
        // SMAPI écrit son diagnostic au **début** du fichier : garder les
        // N dernières lignes jetait exactement ce qui compte.
        let entries = [entry("diagnostic", .warning, .smapi)]
            + (1...10).map { entry("bruit\($0)", .trace, .smapi) }
        let kept = LogBudget.trimPreservingSignal(entries, cap: 3)
        #expect(kept.count == 3)
        #expect(kept.first?.message == "diagnostic")
    }

    @Test func trimmingIsAPassthroughUnderTheCap() {
        let entries = [entry("a"), entry("b")]
        #expect(LogBudget.trimPreservingSignal(entries, cap: 10).map(\.message) == ["a", "b"])
    }

    // MARK: - L'ajout d'une entrée de l'app

    @Test func appendingOverTheCapDropsTheOldest() {
        let existing = (1...3).map { entry("a\($0)") }
        let out = LogBudget.appending(entry("a4"), to: existing, cap: 3)
        #expect(out.map(\.message) == ["a2", "a3", "a4"])
    }

    @Test func appendingUnderTheCapKeepsEverything() {
        let out = LogBudget.appending(entry("a2"), to: [entry("a1")], cap: 10)
        #expect(out.map(\.message) == ["a1", "a2"])
    }
}
