import Testing
import Foundation
@testable import StarHubTHCore

/// Les noms viennent tous d'archives réellement téléchargées, relevées le
/// 2026-08-29 dans le registre des traductions et dans `mods tests/`.
struct NexusArchiveNameTests {

    // MARK: - Forme à espaces (relevée sur 6 archives de 2026)

    @Test func spacedFormYieldsTheIdAndTheVersion() throws {
        let origin = NexusArchiveName.parse(
            "UI Info Suite 2 Alternative FR 46333 2.9.0 2026-08-10T13-50Z Pct026wXo")
        #expect(origin?.modId == 46333)
        #expect(origin?.version == "2.9.0")
    }

    /// **Le piège du premier nombre.** « UI Info Suite **2** Alternative » : un
    /// parseur qui prendrait le premier entier venu rendrait `2`, plausible et
    /// faux. C'est l'horodatage qui ancre, pas la position dans la phrase.
    @Test func aNumberInsideTheNameIsNotTheId() throws {
        #expect(NexusArchiveName.parse(
            "UI Info Suite 2 Alternative FR 46333 2.9.0 2026-08-10T13-50Z Pct026wXo")?
            .modId != 2)
    }

    /// Une version peut n'être qu'un chiffre : `Nyapu Style Lilybrook 50646 1`.
    /// Exiger un point l'aurait écartée.
    @Test func aSingleDigitVersionIsStillAVersion() throws {
        let origin = NexusArchiveName.parse(
            "Nyapu Style Lilybrook 50646 1 2026-08-13T03-28Z Ukcm5deID")
        #expect(origin?.modId == 50646)
        #expect(origin?.version == "1")
    }

    @Test func spacedFormOnTheRestOfTheCorpus() throws {
        let corpus: [(String, Int, String)] = [
            ("The Queen Of Sauce Cookbook - FR 50659 1.0.2 2026-08-13T07-46Z M3Q90NOfa",
             50659, "1.0.2"),
            ("FishingLogbook - FR 50233 1.1.0 2026-08-05T17-33Z 2hI4jbUR4", 50233, "1.1.0"),
            ("Kalash's More Fruit Trees v1.2.1 41318 1.2.1 2026-08-25T12-13Z 5shDRtb8S",
             41318, "1.2.1"),
            ("ModernConfigMenu 49437 1.7.4 2026-08-28T12-27Z IxTXlKuci", 49437, "1.7.4"),
        ]
        for (name, id, version) in corpus {
            let origin = NexusArchiveName.parse(name)
            #expect(origin?.modId == id, "\(name)")
            #expect(origin?.version == version, "\(name)")
        }
    }

    // MARK: - Forme à tirets (horodatage Unix en fin)

    @Test func dashedFormYieldsTheIdAndTheDashedVersion() throws {
        let origin = NexusArchiveName.parse("MakeGuntherRealFR-34339-1-0-1748539543")
        #expect(origin?.modId == 34339)
        #expect(origin?.version == "1.0")
    }

    /// Le nom peut porter sa propre version avant les tirets — elle ne doit pas
    /// être prise pour l'identifiant.
    @Test func aVersionInsideTheNameIsNotTheId() throws {
        #expect(NexusArchiveName.parse(
            "Generic Mod Config Menu 1.16.0-5098-1-16-0-1760816937")?.modId == 5098)
        #expect(NexusArchiveName.parse(
            "Cloths and Colors 1.2.8-43258-1-0-1772792211")?.modId == 43258)
    }

    /// Un nom de dossier du parc réel : des tirets, une version, mais pas
    /// d'horodatage Unix. Rien à en tirer.
    @Test func dashesWithoutATimestampYieldNothing() throws {
        #expect(NexusArchiveName.parse(
            "Quick Chest Categories for Chests Anywhere-1.0.2") == nil)
    }

    // MARK: - Ce qu'il faut refuser

    /// Les quatre noms que le navigateur intégré a enregistrés : leur
    /// identifiant venait de Nexus, pas du nom. Le parseur ne doit rien
    /// inventer sur eux — c'est l'appelant qui garde la main.
    @Test func aNameWithoutAnIdYieldsNothing() throws {
        for name in ["New Item Bags for Sunberry Village",
                     "Item Bags - An Alternative Base-Game Config File",
                     "Item Bags for Wildflour's Atelier Goods",
                     "Item Bags for All Cornucopia",
                     "", "fr", "i18n"] {
            #expect(NexusArchiveName.parse(name) == nil, "\(name)")
        }
    }

    /// L'extension ne fait pas partie du nom relevé par l'app, mais un appelant
    /// pourrait la laisser : elle ne doit pas faire rater l'horodatage.
    @Test func aTrailingExtensionIsIgnored() throws {
        #expect(NexusArchiveName.parse(
            "FishingLogbook - FR 50233 1.1.0 2026-08-05T17-33Z 2hI4jbUR4.7z")?
            .modId == 50233)
    }

    /// Un horodatage sans les deux jetons qu'il faut devant ne conclut rien.
    @Test func aTimestampAloneYieldsNothing() throws {
        #expect(NexusArchiveName.parse("Truc 2026-08-05T17-33Z 2hI4jbUR4") == nil)
        #expect(NexusArchiveName.parse("Truc machin 2026-08-05T17-33Z x") == nil)
    }
}
