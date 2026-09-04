import Foundation
import Testing
@testable import StarHubTHCore

/// Les 24 avertissements du dump Pathoschild, relevés tels quels le
/// 2026-09-05 (4 720 entrées). Aucun exemple inventé : c'est le corpus entier.
private let realWarnings: [(id: String, text: String)] = [
    ("atravita.AtraCore", "Broken on Android."),
    ("KunYai.AutoChestOrganizer", "Only compatible with Android."),
    ("Rakiin.AutomaticGates", "use Nexus, ModDrop is NOT updated"),
    ("spacechase0.BiggerBackpack", "Broken on Android."),
    ("Exohayvan.DissolverEnhanced", "Mod collects telemetry data by default and transmits it to a remote server. This is not disclosed on the mod page."),
    ("tech.enghao.sv.eh-smash-quality", "Only compatible with Android."),
    ("Entoarox.Utilities", "Players report frequent crashes when loading saves or approaching the greenhouse."),
    ("Entoarox.FasterPaths", "Broken on Android (needs Entoarox Framework which crashes on startup)."),
    ("tstaples.GiftTasteHelper", "Needs zoom and UI scale options to have the same value."),
    ("kazutopi1.KT_TriggersAndroid", "Only compatible with Android."),
    ("ekyso.MobileButtonBPolling", "Only compatible with Android."),
    ("WisnuNug.MobileUI", "Only works on Android."),
    ("Omegasis.NightOwl", "Affected by a Vortex mod manager bug; use [Night Owl Repacked](https://www.nexusmods.com/stardewvalley/mods/19291) if you use Vortex."),
    ("Priff13.NPCMapLocations_Android", "Only compatible with Android."),
    ("Aedenthorn.RandomNPC", "Doesn't work in multiplayer."),
    ("EternalSoap.RemoteFridgeStorage", "Broken on Android (loads but does not work)."),
    ("Omegasis.SaveAnywhere", "Broken on Android (use the built-in autosave instead)."),
    ("kazutopi1.ShopAnywhereAndroid", "Only compatible with Android."),
    ("Entoarox.ShopExpander", "Broken on Android (needs Entoarox Framework which crashes on startup)."),
    ("cctz_hm.Teleport", "Released mod has incorrect file structure; open the download, unzip the file at 'bin/Debug/net6.0/Teleport 1.0.0.zip', and put that unzipped folder in your Mods folder instead."),
    ("Annosz.UiInfoSuite2", "Broken on Android. See [UI Info Suite 2 for Android](#) or [UI Info Suite 2 Redux](#) for Android support."),
    ("Priff13.UIInfoSuite2_Android", "Only compatible with Android."),
    ("Ekyso.UiInfoSuite2Redux", "Only compatible with Android."),
    ("RomValim.VirtualKeyboard2", "Only compatible with Android."),
]

@Suite struct ModPlatformWarningsTests {

    // MARK: - Le corpus réel

    /// Le compte que la ROADMAP annonçait, reproduit par la règle : **17**
    /// avertissements ne parlent que d'Android, **1** ne parle que d'un
    /// magasin de téléchargement qu'on n'utilise pas, et **6** valent la
    /// lecture. Si ce test tombe, c'est que la règle a bougé ou que le dump a
    /// changé — les deux méritent d'être regardés.
    @Test func theWholeCorpusSplitsAsMeasured() {
        var other = 0, source = 0, worth = 0
        for entry in realWarnings {
            switch ModPlatformWarnings.relevance(of: entry.text) {
            case .otherPlatform: other += 1
            case .downloadSource: source += 1
            case .worthReading: worth += 1
            }
        }
        #expect(other == 17)
        #expect(source == 1)
        #expect(worth == 6)
    }

    /// Les six qui restent, nommément : les taire serait perdre la seule
    /// alerte de télémétrie non divulguée du dump.
    @Test func theSixWorthReadingAreTheExpectedOnes() {
        let kept = realWarnings
            .filter { ModPlatformWarnings.relevance(of: $0.text) == .worthReading }
            .map(\.id)
        #expect(kept == ["Exohayvan.DissolverEnhanced",
                         "Entoarox.Utilities",
                         "tstaples.GiftTasteHelper",
                         "Omegasis.NightOwl",
                         "Aedenthorn.RandomNPC",
                         "cctz_hm.Teleport"])
    }

    // MARK: - Ce que la règle ne doit PAS écarter

    /// **Le voisin qu'un `contains("android")` naïf perdrait.** Un
    /// avertissement qui nomme Android *et* notre plateforme nous concerne :
    /// l'écarter ferait taire un mod réellement cassé ici.
    @Test func aWarningNamingBothAndroidAndOurPlatformIsKept() {
        #expect(ModPlatformWarnings.relevance(of: "Broken on Android and macOS.")
                == .worthReading)
        #expect(ModPlatformWarnings.relevance(of: "Broken on Mac and Android.")
                == .worthReading)
        #expect(ModPlatformWarnings.relevance(of: "Broken on all platforms, including Android.")
                == .worthReading)
    }

    /// **Le piège de la sous-chaîne nue.** « ios » vit à l'intérieur de
    /// « ratios » et de « kiosk » ; « pc » et « mac » sont tout aussi courts.
    /// Un faux positif du côté « plateforme étrangère » **masque** un
    /// avertissement réel — c'est le sens dangereux.
    @Test func aWordThatMerelyContainsAPlatformNameIsNotAPlatformName() {
        #expect(ModPlatformWarnings.relevance(of: "Breaks at unusual aspect ratios.")
                == .worthReading)
        #expect(ModPlatformWarnings.relevance(of: "The kiosk menu never opens.")
                == .worthReading)
    }

    /// Un avertissement qui ne nomme aucune plateforme est gardé : le silence
    /// n'est pas une preuve qu'il concerne quelqu'un d'autre.
    @Test func aWarningNamingNoPlatformIsKept() {
        #expect(ModPlatformWarnings.relevance(of: "Corrupts saves after year 3.")
                == .worthReading)
    }

    /// Nommer ModDrop ne suffit pas : seul le renvoi vers une autre source de
    /// téléchargement est du bruit. Un vrai défaut qui mentionne ModDrop reste.
    @Test func aRealDefectThatMerelyMentionsModDropIsKept() {
        #expect(ModPlatformWarnings.relevance(of: "The ModDrop build corrupts saves.")
                == .worthReading)
    }

    // MARK: - Le tamis complet

    /// Ce que l'appelant utilise : la liste réduite à ce qui nous concerne,
    /// dans l'ordre d'origine.
    @Test func theSieveKeepsOrderAndDropsTheRest() {
        let kept = ModPlatformWarnings.worthReading([
            "Broken on Android.",
            "Doesn't work in multiplayer.",
            "use Nexus, ModDrop is NOT updated",
            "Corrupts saves after year 3.",
        ])
        #expect(kept == ["Doesn't work in multiplayer.", "Corrupts saves after year 3."])
    }

    /// Le balisage Markdown du dump ne doit pas s'afficher tel quel : deux des
    /// six avertissements gardés portent un lien, et `ModCompatibility` sait
    /// déjà les séparer pour le champ voisin (`summary`). Une seconde règle de
    /// lecture aurait divergé de la première.
    @Test func markdownLinksAreReducedToTheirLabel() {
        let raw = "Affected by a Vortex mod manager bug; use "
            + "[Night Owl Repacked](https://www.nexusmods.com/stardewvalley/mods/19291) "
            + "if you use Vortex."
        let kept = ModPlatformWarnings.worthReading([raw])

        #expect(kept.first?.contains("Night Owl Repacked") == true)
        #expect(kept.first?.contains("](") == false)
        #expect(kept.first?.contains("https://") == false)
    }

    /// Une entrée vide ou blanche n'est pas un avertissement.
    @Test func blankWarningsAreDropped() {
        #expect(ModPlatformWarnings.worthReading(["", "   ", "\n"]).isEmpty)
    }
}
