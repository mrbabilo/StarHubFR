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

/// Le bloc « You can update N mods: » que SMAPI écrit au démarrage. C'est la
/// source des mises à jour signalées hors Nexus : compteur de la barre
/// latérale, écran Updates, pied de page.
struct SmapiUpdateBlockTests {
    /// Format réel : SMAPI intercale une ligne vide entre les entrées, y
    /// compris juste après l'en-tête. L'ancien découpage traitait toute ligne
    /// sans « ALERT SMAPI » comme la fin du bloc, donc il s'arrêtait avant
    /// d'avoir lu une seule entrée — aucune mise à jour n'était jamais
    /// détectée. Défaut relevé en amont (AppleBoiy/StarHubTH, 6306958) sur un
    /// journal réel de 122 000 lignes.
    @Test func blankLinesBetweenEntriesDoNotEndTheBlock() {
        let log = """
        [12:00:00 ALERT SMAPI] You can update 2 mods:

        [12:00:00 ALERT SMAPI]    Content Patcher 2.0.0: https://smapi.io/mods#Content_Patcher

        [12:00:00 ALERT SMAPI]    Automate 2.3.1: https://smapi.io/mods#Automate

        [12:00:01 INFO  SMAPI] Launching mods...
        """
        let out = SmapiLogParser.updates(in: log)
        #expect(out.map(\.name) == ["Content Patcher", "Automate"])
        #expect(out.map(\.version) == ["2.0.0", "2.3.1"])
        #expect(out.first?.url == "https://smapi.io/mods#Content_Patcher")
    }

    @Test func aNonBlankNonAlertLineStillEndsTheBlock() {
        let log = """
        [12:00:00 ALERT SMAPI] You can update 1 mod:
        [12:00:00 ALERT SMAPI]    Automate 2.3.1: https://smapi.io/mods#Automate
        [12:00:01 INFO  SMAPI] Launching mods...
        [12:00:02 ALERT SMAPI]    NotAnUpdate 1.0: https://example.com/x
        """
        #expect(SmapiLogParser.updates(in: log).map(\.name) == ["Automate"])
    }

    @Test func aLogWithNoUpdateBlockYieldsNothing() {
        #expect(SmapiLogParser.updates(in: "[12:00:00 INFO  SMAPI] Loaded 900 mods").isEmpty)
    }

    @Test func aModNameWithSpacesKeepsThemAndOnlyTheVersionIsSplitOff() {
        let log = """
        [12:00:00 ALERT SMAPI] You can update 1 mod:

        [12:00:00 ALERT SMAPI]    Stardew Valley Expanded 1.14.20: https://smapi.io/mods#SVE
        """
        let out = SmapiLogParser.updates(in: log)
        #expect(out.first?.name == "Stardew Valley Expanded")
        #expect(out.first?.version == "1.14.20")
    }

    @Test func theUpdateUrlStopsBeforeTheInstalledVersion() throws {
        // Ligne réelle du journal de l'auteur (2026-09-01) : SMAPI accole la
        // version installée derrière l'URL. `URL(string:)` ne refuse pas
        // l'espace — il l'encode — donc le bouton menait à un 404 et le lien
        // affichait `…/releases%20(you%20have%201.6.1-unofficial-2.dphill)`.
        let log = """
        [17:40:11 ALERT SMAPI] You can update 1 mod:
        [17:40:11 ALERT SMAPI]    Mod Update Menu 2.7.0: https://github.com/Dphill10827/UnofficialModUpdateMenu/releases (you have 1.6.1-unofficial-2.dphill)
        """
        let updates = SmapiLogParser.updates(in: log)
        #expect(updates.count == 1)
        let update = try #require(updates.first)
        #expect(update.name == "Mod Update Menu")
        #expect(update.version == "2.7.0")
        #expect(update.url == "https://github.com/Dphill10827/UnofficialModUpdateMenu/releases")
        // Ce que l'écran en fait : deux `URL(string:)`, un bouton et un lien.
        let url = try #require(URL(string: update.url))
        #expect(!url.absoluteString.contains("%20"))
        #expect(url.absoluteString == update.url)
    }

    @Test func anUrlWithoutATrailingNoteIsUntouched() {
        // La borne : la forme sans parenthèse ne doit rien perdre.
        let log = "[12:00:00 ALERT SMAPI]    Content Patcher 2.0.0: https://smapi.io/mods#Pathoschild.ContentPatcher"
        let updates = SmapiLogParser.updates(in: "You can update 1 mod:\n" + log)
        #expect(updates.first?.url == "https://smapi.io/mods#Pathoschild.ContentPatcher")
    }


    // MARK: - Imputations devinées

    @Test func aNameFromTheBracketIsNotInferred() throws {
        let entries = SmapiLogParser.parse(
            "[12:00:00 ERROR Content Patcher] Something broke: badly")
        let entry = try #require(entries.first)
        #expect(entry.modName == "Content Patcher")
        #expect(entry.modNameIsInferred == false)
    }

    @Test func aNameFromTheMessagePrefixIsInferred() throws {
        // Le cas pour lequel l'heuristique existe : SMAPI journalise l'erreur
        // d'un mod sous son propre crochet, le nom n'est qu'en tête du message.
        let entries = SmapiLogParser.parse(
            "[12:00:00 ERROR SMAPI] Gunther's Guide: Tried to map a null entry")
        let entry = try #require(entries.first)
        #expect(entry.modName == "Gunther's Guide")
        #expect(entry.modNameIsInferred == true)
    }

    @Test func anInferredNameThatIsNoModIsDropped() throws {
        // Les trois faux coupables du journal réel de l'auteur (2026-09-01).
        let log = """
        [17:40:11 ALERT SMAPI] You can update 1 mod:
        [17:40:12 ERROR SMAPI] Galaxy auth failure: FAILURE_REASON_GALAXY_SERVICE_NOT_SIGNED_IN
        [17:40:13 ERROR SMAPI] Gunther's Guide: Tried to map a null entry
        """
        let parsed = SmapiLogParser.parse(log)
        #expect(parsed.compactMap(\.modName).count == 3)
        let cleaned = SmapiLogParser.dismissingUnknownInferredMods(parsed) {
            $0 == "Gunther's Guide"
        }
        #expect(cleaned.compactMap(\.modName) == ["Gunther's Guide"])
        // Le drapeau tombe avec le nom : une ligne sans imputation n'en a plus
        // de devinée non plus.
        #expect(cleaned.filter(\.modNameIsInferred).count == 1)
    }

    @Test func aBracketNameSurvivesAnUnknownMod() throws {
        // Un mod désinstallé depuis le dernier lancement du jeu reste nommé :
        // SMAPI l'affirme, ce n'est pas une devinette.
        let parsed = SmapiLogParser.parse("[12:00:00 ERROR Retired Mod] boom: here")
        let cleaned = SmapiLogParser.dismissingUnknownInferredMods(parsed) { _ in false }
        #expect(cleaned.first?.modName == "Retired Mod")
    }

    @Test func theSameInferredNameIsJudgedOnce() {
        // La résolution parcourt tout le parc : le verdict est mémorisé.
        let log = (1...5).map { i in
            "[12:00:0\(i) ERROR SMAPI] Phantom Thing: boom \(i)"
        }.joined(separator: "\n")
        var calls = 0
        let cleaned = SmapiLogParser.dismissingUnknownInferredMods(SmapiLogParser.parse(log)) { _ in
            calls += 1
            return false
        }
        #expect(cleaned.compactMap(\.modName).isEmpty)
        #expect(calls == 1)
    }

}
