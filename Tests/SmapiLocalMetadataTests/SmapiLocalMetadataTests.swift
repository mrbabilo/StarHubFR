import Foundation
import Testing
@testable import StarHubTHCore

/// A2-T5 — le filet local `smapi-internal/metadata.json` (volet compat de
/// `ModData`) : parse JSONC, clause de version **obligatoire**. Fixture =
/// copie du vrai fichier de l'installation de l'auteur (SMAPI 4.15.9,
/// 2026-10-07), et le tableau des 17 mods de son parc qu'il couvre — relevé,
/// pas inventé : 0 signal réel, 14 faux positifs si les bornes sont ignorées.
@Suite struct SmapiLocalMetadataTests {

    static let fixture: String = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/metadata.jsonc")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    /// `(UniqueID, version installée)` des 17 manifestes du parc couverts par
    /// la fixture — mesuré le 2026-10-07.
    static let parc: [(id: String, version: String)] = [
        ("Advize.LovedLabels", ""),
        ("Cherry.ShopTileFramework", "1.0.13"),
        ("DIGUS.MailFrameworkMod", "1.20.0"),
        ("FlashShifter.SVECode", "1.15.11"),
        ("FlyingTNT.Swim", "1.9.0"),
        ("NCarigon.PassableCrops", "1.2.3"),
        ("Pathoschild.ContentPatcher", "2.9.1"),
        ("Pathoschild.SkipIntro", "1.9.25"),
        ("aedenthorn.AllChestsMenu", "0.4.2"),
        ("bcmpinc.MovementSpeed", "7.3"),
        ("bcmpinc.StardewHack", "7.4"),
        ("bcmpinc.WearMoreRings", "7.9"),
        ("com.anthonyhilyard.CatalogueIndicator", "1.0.1"),
        ("gizzymo.canonfriendlyexpansion", "3.1.1"),
        ("spacechase0.JsonAssets", "1.11.11"),
        ("spacechase0.SpaceCore", "1.28.4"),
        ("tlitookilakin.HappyHomeDesigner", "2.6.0"),
    ]

    @Test func parsesTheRealFile() {
        let index = SmapiLocalMetadata.parse(Self.fixture)
        // 188 entrées dans le fichier, 178 portent une clause Status (les
        // 10 autres n'ont qu'un UpdateKey : rien à dire en compat).
        #expect(index.count == 178)
        #expect(index["flashshifter.svecode"] != nil)
        #expect(index["gpeters-animalmoodfix"] != nil)
    }

    /// La mesure de la ROADMAP, rejouée : sur les 17 mods couverts du parc,
    /// aucun verdict — chacun est au-dessus de sa borne ou sans version lisible.
    @Test func theWholeParcStaysSilent() {
        let index = SmapiLocalMetadata.parse(Self.fixture)
        let verdicts = SmapiLocalMetadata.verdicts(for: Self.parc, from: index)
        #expect(verdicts.isEmpty)
    }

    @Test func aModBelowItsBoundIsBrokenWithTheSMAPIReason() throws {
        let index = SmapiLocalMetadata.parse(Self.fixture)
        // SVE est `AssumeBroken` sous 1.13.11 : une 1.12.9 l'était vraiment.
        let verdicts = SmapiLocalMetadata.verdicts(
            for: [("FlashShifter.SVECode", "1.12.9")], from: index)
        let sve = try #require(verdicts["FlashShifter.SVECode"])
        #expect(sve.status == .broken)
        // La raison écrite par SMAPI elle-même, telle quelle.
        #expect(sve.summary.contains("ICue"))
        // Une entrée `Obsolete` sans borne s'applique à toute version.
        let obsolete = try #require(SmapiLocalMetadata.verdicts(
            for: [("GPeters-AnimalMoodFix", "9.9.9")], from: index)["GPeters-AnimalMoodFix"])
        #expect(obsolete.status == .obsolete)
    }

    @Test func anUnreadableVersionNeverTriggersABoundedClause() {
        let index = SmapiLocalMetadata.parse(Self.fixture)
        // Loved Labels : version illisible au manifeste, entrée bornée — muet.
        #expect(SmapiLocalMetadata.verdicts(for: [("Advize.LovedLabels", "")], from: index).isEmpty)
    }

    @Test func unknownStatusValuesStaySilentToo() {
        let index = SmapiLocalMetadata.parse(Self.fixture)
        let verdicts = SmapiLocalMetadata.verdicts(for: [("Someone.NewMod", "1.0"), ("spacechase0.SpaceCore", "1.28.4")],
                                                   from: index)
        #expect(verdicts["Someone.NewMod"] == nil)
    }

    /// Le garde anti-retour : ignorer les bornes signalerait 14 mods sains.
    /// Si ce test rougit après un « simplification » du parseur, c'est lui qui
    /// a raison.
    @Test func ignoringTheBoundsWouldFlagFourteenHealthyMods() {
        let index = SmapiLocalMetadata.parse(Self.fixture)
        var flagged = 0
        for mod in Self.parc {
            if SmapiLocalMetadata.statusIgnoringBounds(for: mod.id, in: index) != nil { flagged += 1 }
        }
        #expect(flagged == 14)
    }
}
