import Testing
import Foundation
@testable import StarHubTHCore

/// Le découpage du journal de SMAPI en lignes exploitables. Il vivait dans le
/// ViewModel, donc hors de portée des tests, alors que c'est lui qui décide à
/// qui une erreur est imputée — la question que pose toute la recherche guidée.
struct SmapiLogParserTests {
    @Test func aStandardLineIsSplitIntoItsParts() {
        let out = SmapiLogParser.parse("[12:30:45 ERROR Automate] Something broke")
        #expect(out.count == 1)
        #expect(out[0].timestamp == "12:30:45")
        #expect(out[0].level == .error)
        #expect(out[0].modName == "Automate")
        #expect(out[0].message == "Something broke")
    }

    @Test func smapiAndGameAreNotModNames() {
        // Le crochet porte la source, pas un mod : ne rien imputer à « SMAPI ».
        let out = SmapiLogParser.parse("[12:30:45 INFO  SMAPI] Loaded 900 mods\n[12:30:46 INFO  game] Launching")
        #expect(out.count == 2)
        #expect(out.allSatisfy { $0.modName == nil })
    }

    @Test func anErrorSmapiWritesForAModIsAttributedToThatMod() {
        // Le cas trouvé en conditions réelles : le crochet dit « SMAPI », le nom
        // du mod n'est qu'un préfixe du message.
        let line = "[12:30:45 ERROR SMAPI] Gunther's Guide: Tried to map a mod-provided API"
        #expect(SmapiLogParser.parse(line).first?.modName == "Gunther's Guide")
    }

    @Test func anInfoLineGetsNoPrefixAttribution() {
        // Seuls les avertissements et erreurs sont lus ainsi : un message
        // d'information contenant un deux-points n'accuse personne.
        let line = "[12:30:45 INFO  SMAPI] Mods loaded: 900 mods"
        #expect(SmapiLogParser.parse(line).first?.modName == nil)
    }

    @Test func alertCountsAsAWarningAndUnknownLevelsAsTrace() {
        let out = SmapiLogParser.parse("[1 ALERT SMAPI] a\n[2 DEBUG SMAPI] b")
        #expect(out.map(\.level) == [.warning, .trace])
    }

    @Test func aContinuationLineIsFoldedIntoTheEntryAbove() {
        // Une trace d'exécution occupe des dizaines de lignes sans en-tête :
        // elles appartiennent à l'erreur qui précède, pas à des entrées à part.
        let out = SmapiLogParser.parse("""
        [12:30:45 ERROR Automate] Boom
           at Automate.Machine.Update()
           at StardewValley.Game1.Update()
        """)
        #expect(out.count == 1)
        #expect(out[0].message.contains("at Automate.Machine.Update()"))
        #expect(out[0].modName == "Automate")
    }

    @Test func aContinuationLineWithNoEntryAboveIsDropped() {
        #expect(SmapiLogParser.parse("   orpheline\n[1 INFO SMAPI] x").count == 1)
    }

    @Test func aMalformedHeaderIsSkippedRatherThanGuessed() {
        // Crochet ouvrant jamais refermé : mieux vaut perdre la ligne que
        // fabriquer une entrée dont le message serait le journal entier.
        #expect(SmapiLogParser.parse("[12:30:45 ERROR Automate no closing bracket").isEmpty)
    }

    @Test func everyEntryComesFromTheSmapiLog() {
        let out = SmapiLogParser.parse("[1 INFO SMAPI] x")
        #expect(out.allSatisfy { $0.source == .smapi })
    }
}
