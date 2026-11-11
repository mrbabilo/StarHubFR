import Testing
import Foundation
@testable import StarHubTHCore

/// UltraSmooth 2.8.x écrit ses exceptions rattrapées en TRACE
/// (`UltraSmoothLogger.ErrorOnce`, `docs/audit-ultrasmooth-2.8.4.md`) :
/// l'app les relève au rang d'erreur, et rien d'autre.
struct LoggedOnceErrorTests {
    /// Forme exacte de la 2.8.4 : `<clé> failed (logged once): <type>: <message>`,
    /// sous la source « Ultra Smooth » (le `Name` de son manifeste).
    static let line = "[06:10:02 TRACE Ultra Smooth] BatchSerialization.MarginRef failed (logged once): NullReferenceException: Object reference not set to an instance of an object."

    @Test func theTraceLineBecomesAnErrorOfUltraSmooth() throws {
        let entry = try #require(SmapiLogParser.parse(Self.line).first)
        #expect(entry.level == .error)
        #expect(entry.modName == "Ultra Smooth")
        #expect(entry.message.hasPrefix("BatchSerialization.MarginRef failed (logged once)"))
    }

    /// Compte dans les erreurs par mod des diagnostics (`topErrorMods`).
    @Test func itCountsInTheDiagnosticsErrorTally() {
        let d = SmapiDiagnostics.parse(logContent: [Self.line, Self.line].joined(separator: "\r\n"))
        #expect(d.topErrorMods.first?.name == "Ultra Smooth")
        #expect(d.topErrorMods.first?.count == 2)
    }

    /// Une TRACE ordinaire d'UltraSmooth reste du bruit.
    @Test func anOrdinaryTraceStaysTrace() throws {
        let entry = try #require(SmapiLogParser.parse("[06:10:02 TRACE Ultra Smooth] Time-slicing 12 locations").first)
        #expect(entry.level == .trace)
        #expect(SmapiDiagnostics.parse(logContent: "[06:10:02 TRACE Ultra Smooth] Time-slicing 12 locations").topErrorMods.isEmpty)
    }

    /// La formule chez un autre mod, ou à un autre niveau, ne change rien :
    /// la règle vise l'écriture d'UltraSmooth, pas une phrase.
    @Test func theRuleIsNarrow() throws {
        let other = "[06:10:02 TRACE Some Mod] Foo failed (logged once): X: y"
        #expect(try #require(SmapiLogParser.parse(other).first).level == .trace)
        let debug = "[06:10:02 DEBUG Ultra Smooth] Foo failed (logged once): X: y"
        #expect(try #require(SmapiLogParser.parse(debug).first).level != .error)
        let smapi = "[06:10:02 TRACE SMAPI] Foo failed (logged once): X: y"
        #expect(try #require(SmapiLogParser.parse(smapi).first).level == .trace)
    }

    /// Le résumé des lignes dupliquées d'UltraSmooth compare les niveaux de la
    /// ligne citée et de l'entrée : relevés au même endroit, ils concordent.
    @Test func theDuplicateSummaryStillRepeatsAPromotedLine() {
        let summary = "[UltraSmooth SMAPI Optimizer] Suppressed 3 duplicate log lines: \"\(Self.line.prefix(80))...\""
        let entries = SmapiLogParser.parse([Self.line, summary].joined(separator: "\n"))
        #expect(entries.count == 4)
        #expect(entries.allSatisfy { $0.level == .error })
        #expect(entries.allSatisfy(LoggedOnceError.isPromoted))
    }

    /// `isPromoted` ne désigne que les lignes relevées : pas une vraie ERROR.
    @Test func aGenuineErrorIsNotMarkedPromoted() throws {
        let entry = try #require(SmapiLogParser.parse("[06:10:02 ERROR Ultra Smooth] Crash in X").first)
        #expect(!LoggedOnceError.isPromoted(entry))
    }
}
