import Testing
import Foundation
@testable import StarHubTHCore

/// X140 — UltraSmooth (`EnableSmapiOptimizer`, actif par défaut) écrit le
/// journal de SMAPI à sa place : au-delà de cinq lignes identiques
/// consécutives, il remplace les suivantes par une ligne de résumé de son cru.
/// Lue telle quelle, cette ligne devenait une entrée « trace » datée
/// « UltraSmooth » et imputée à un mod « Optimizer », et l'erreur répétée ne
/// comptait que cinq fois.
struct UltraSmoothLogSummaryTests {
    private let line = "[12:00:01 ERROR Automate] Machine failed"

    private func log(_ lines: [String]) -> String { lines.joined(separator: "\n") }

    @Test func aSummaryRestoresTheSuppressedRepeats() {
        let text = log(Array(repeating: line, count: 5) + [
            "[UltraSmooth SMAPI Optimizer] Suppressed 12 duplicate log lines: \"\(line)\"",
        ])
        let out = SmapiLogParser.parse(text)
        #expect(out.count == 17)
        #expect(out.allSatisfy { $0.modName == "Automate" && $0.level == .error })
        #expect(out.allSatisfy { $0.message == "Machine failed" })
    }

    @Test func aTruncatedQuoteStillMatchesTheRepeatedLine() {
        // UltraSmooth coupe la citation à 80 caractères et ajoute « ... ».
        let long = "[12:00:01 WARN  Content Patcher] " + String(repeating: "x", count: 120)
        let quote = String(long.prefix(80)) + "..."
        let text = log([long, "[UltraSmooth SMAPI Optimizer] Suppressed 3 duplicate log lines: \"\(quote)\""])
        let out = SmapiLogParser.parse(text)
        #expect(out.count == 4)
        #expect(out.allSatisfy { $0.modName == "Content Patcher" })
    }

    @Test func aSummaryThatQuotesAnotherLineAddsNothing() {
        // La citation doit désigner la dernière entrée : sinon on ne sait pas
        // ce qui a été supprimé, et on n'invente rien.
        let text = log([line, "[UltraSmooth SMAPI Optimizer] Suppressed 4 duplicate log lines: \"[12:00:02 INFO  game] other\""])
        let out = SmapiLogParser.parse(text)
        #expect(out.count == 1)
        #expect(out.allSatisfy { $0.modName == "Automate" })
    }

    @Test func aSummaryNeverBecomesAnEntryOfItsOwn() {
        let text = log(["[UltraSmooth SMAPI Optimizer] Suppressed 4 duplicate log lines: \"\(line)\""])
        #expect(SmapiLogParser.parse(text).isEmpty)
    }

    @Test func aRepeatedMultiLineErrorKeepsItsTrace() {
        // La citation coupée peut contenir le saut de ligne d'une trace : la
        // fin de la citation, à la ligne suivante, ne rejoint pas la copie.
        let text = log([
            "[12:00:01 ERROR Automate] Machine failed",
            "   at Automate.Run()",
            "[UltraSmooth SMAPI Optimizer] Suppressed 2 duplicate log lines: \"[12:00:01 ERROR Automate] Machine failed",
            "   at Automa...\"",
        ])
        let out = SmapiLogParser.parse(text)
        #expect(out.count == 3)
        #expect(out.allSatisfy { $0.message == "Machine failed\nat Automate.Run()" })
    }
}
