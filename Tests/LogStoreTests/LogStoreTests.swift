import Testing
import Foundation
@testable import StarHubTHCore

/// Le porteur des entrées. La règle est prouvée dans `LogBudgetTests` ; ici,
/// c'est qu'il l'applique — et qu'il tient son plafond d'un appel à l'autre.
@Suite struct LogStoreTests {

    private func entry(_ message: String, _ source: LogSource = .app) -> LogEntry {
        LogEntry(timestamp: "00:00:00", message: message, level: .info, source: source)
    }

    @Test func aNewStoreIsEmpty() {
        #expect(LogStore().entries.isEmpty)
    }

    @Test func appendingKeepsOrderAndHoldsTheCap() {
        let s = LogStore(cap: 2)
        s.append(entry("a1")); s.append(entry("a2")); s.append(entry("a3"))
        #expect(s.entries.map(\.message) == ["a2", "a3"])
    }

    /// « Vider les journaux » ne vide que ce que StarHubFR a écrit : le bloc
    /// SMAPI est relu d'un fichier, l'effacer ne ferait que le faire revenir
    /// au prochain rechargement — et entre-temps la liste et la carte de
    /// santé se contrediraient.
    @Test func clearingAppEntriesKeepsTheSmapiBlock() {
        let s = LogStore(cap: 10)
        s.append(entry("app"))
        s.replaceSmapi(with: [entry("smapi", .smapi)])
        s.clearApp()
        #expect(s.entries.map(\.message) == ["smapi"])
    }

    @Test func replacingSmapiLeavesTheAppEntriesAlone() {
        let s = LogStore(cap: 10)
        s.append(entry("app"))
        s.replaceSmapi(with: [entry("s1", .smapi)])
        s.replaceSmapi(with: [entry("s2", .smapi)])
        #expect(s.entries.map(\.message) == ["app", "s2"])
    }
}
