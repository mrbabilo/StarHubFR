import Testing
import Foundation
@testable import StarHubTHCore

/// F6-T3 — les alertes du volet santé (`smapiErrors`) passent par le même
/// lecteur d'en-tête que les Journaux, plus par un second scanner du
/// ViewModel. La règle reprise du scanner : erreurs de la source `SMAPI`
/// seulement, sans l'en-tête du bloc « Skipped mods » ni sa mise en page.
struct SmapiErrorsTests {
    /// Lignes réelles du journal du 2026-10-07 (parc de l'auteur), fins de
    /// ligne CRLF comme sur le disque.
    static let realLog = [
        "[16:42:17 INFO  SMAPI]    ZH's Fancy Grub - Ridgeside Village 1.0.0 by ZoeyHoshi | for Content Patcher | Retexture of cooked items added by Ridgeside Village",
        "",
        "[16:42:17 ERROR SMAPI]    Skipped mods",
        "[16:42:17 ERROR SMAPI]    --------------------------------------------------",
        "[16:42:17 ERROR SMAPI]       These mods could not be added to your game.",
        "",
        "[16:42:17 ERROR SMAPI]       - (AT) Vanilla Forage Crops and Bushes 1.0.3 because it requires mods which aren't installed (PeacefulEnd.AlternativeTextures).",
        "",
        "[16:42:29 ERROR (C#) Sunberry Village] Harmony patch <CJBPatches::ShouldFreezeTime_Transpiler> has encountered an error while attempting to transpile <CJBCheatsMenu.Framework.Cheats.Time.FreezeTimeCheat::ShouldFreezeTime>: ",
        "[16:44:01 ERROR game] Galaxy auth failure: FAILURE_REASON_GALAXY_SERVICE_NOT_SIGNED_IN",
    ].joined(separator: "\r\n")

    /// Seule la ligne du mod ignoré reste : l'en-tête et la mise en page du
    /// bloc tombent, l'erreur d'un mod (source nommée) et celle du jeu
    /// (`game`, l'authentification GOG) ne sont pas des alertes de SMAPI.
    @Test func keepsOnlySmapiOwnErrors() {
        #expect(SmapiLogParser.smapiErrors(in: Self.realLog) == [
            "- (AT) Vanilla Forage Crops and Bushes 1.0.3 because it requires mods which aren't installed (PeacefulEnd.AlternativeTextures).",
        ])
    }

    /// Une trace sous l'erreur ne s'ajoute pas au message : l'alerte garde
    /// sa première ligne, comme le scanner qu'elle remplace.
    @Test func continuationLinesStayOut() {
        let log = "[10:00:00 ERROR SMAPI] Failed loading something\r\n   at Foo.Bar()\r\n   at Baz()"
        #expect(SmapiLogParser.smapiErrors(in: log) == ["Failed loading something"])
    }

    /// Une erreur répétée ne compte qu'une fois, dans l'ordre d'apparition,
    /// et le volet n'en montre que dix.
    @Test func deduplicatesAndCaps() {
        let lines = (0..<12).map { "[10:00:0\($0 % 10) ERROR SMAPI] erreur \($0)" }
        let log = (["[09:59:59 ERROR SMAPI] erreur 3"] + lines).joined(separator: "\n")
        let errors = SmapiLogParser.smapiErrors(in: log)
        #expect(errors.count == 10)
        #expect(errors.first == "erreur 3")
        #expect(errors.filter { $0 == "erreur 3" }.count == 1)
    }

    /// Le niveau compte : un `WARN SMAPI` n'est pas une alerte d'erreur.
    @Test func warningsStayOut() {
        #expect(SmapiLogParser.smapiErrors(in: "[10:00:00 WARN  SMAPI] attention").isEmpty)
    }

    /// Le découpage partagé ne change rien aux Journaux : mêmes entrées.
    @Test func parseStillReadsTheSameLines() {
        let entries = SmapiLogParser.parse(Self.realLog)
        #expect(entries.count == 7)
        #expect(entries[5].modName == "(C#) Sunberry Village")
    }
}
