import Testing
import Foundation
@testable import StarHubTHCore

/// Les résumés sont ceux que smapi.io a réellement rendus le 2026-08-25 pour
/// les sept mods signalés du parc — pas des exemples inventés. Le format n'est
/// documenté nulle part ; ces phrases sont la seule spécification qui existe.
struct ModCompatibilityTests {

    @Test func aReplacementModIsPulledOutOfTheSentence() throws {
        let raw = "⚠ use [Train Tracks - Continued](https://www.nexusmods.com/stardewvalley/mods/28049) instead."
        let verdict = try #require(ModCompatibility.from(
            status: "Workaround", brokeIn: "Stardew Valley 1.6", summary: raw))
        #expect(verdict.status == .workaround)
        #expect(verdict.brokeIn == "Stardew Valley 1.6")
        // L'avertissement de tête part : l'icône le porte déjà.
        #expect(verdict.summary == "use Train Tracks - Continued instead.")
        #expect(verdict.links == [.init(label: "Train Tracks - Continued",
                                        url: "https://www.nexusmods.com/stardewvalley/mods/28049")])
    }

    /// Deux voies proposées, dans l'ordre où la phrase les cite.
    @Test func twoLinksKeepTheirOrder() throws {
        let raw = "⚠ use [unofficial update](https://forums.stardewvalley.net/threads/x.2096/post-123243)"
            + " or [Informant - The Tooltip Labels](https://www.nexusmods.com/stardewvalley/mods/21286) instead."
        let verdict = try #require(ModCompatibility.from(
            status: "Workaround", brokeIn: nil, summary: raw))
        #expect(verdict.links.map(\.label) == ["unofficial update", "Informant - The Tooltip Labels"])
        #expect(verdict.summary == "use unofficial update or Informant - The Tooltip Labels instead.")
    }

    /// **Le `<small>` encadre le numéro de version à installer** : on retire la
    /// balise, jamais son contenu.
    @Test func theVersionInsideSmallTagsSurvives() throws {
        let raw = "broken, use [unofficial version](https://github.com/Xytronix/BusLocations/releases)"
            + " (<small>1.2.2-unofficial.1-Xytronix</small>)."
        let verdict = try #require(ModCompatibility.from(
            status: "Unofficial", brokeIn: "Stardew Valley 1.6", summary: raw))
        #expect(verdict.summary == "broken, use unofficial version (1.2.2-unofficial.1-Xytronix).")
        #expect(verdict.links.first?.url == "https://github.com/Xytronix/BusLocations/releases")
    }

    /// **Un statut inconnu ne devient pas « sain ».** smapi.io peut en ajouter
    /// un demain ; le ranger d'office parmi les vérifiés serait le pire des deux.
    @Test func anUnknownStatusYieldsNothing() {
        #expect(ModCompatibility.from(status: "Sideways", brokeIn: nil, summary: "") == nil)
        #expect(ModCompatibility.from(status: nil, brokeIn: nil, summary: "x") == nil)
    }

    /// `Ok` est retenu, et ne demande rien. Sans lui, « vérifié et sain » se
    /// confondrait avec « inconnu » — or 552 mods sur 840 sont inconnus.
    @Test func okIsKeptButAsksForNothing() throws {
        let verdict = try #require(ModCompatibility.from(status: "Ok", brokeIn: nil, summary: nil))
        #expect(verdict.status == .ok)
        #expect(!verdict.status.needsAttention)
        #expect(verdict.summary.isEmpty)
        #expect(ModCompatibility.Status.unofficial.needsAttention)
    }

    /// Un pack porte le verdict du plus grave de ses composants : c'est le
    /// dossier qu'on active, pas ses enfants.
    @Test func severityOrdersTheVerdicts() {
        let ordered: [ModCompatibility.Status] =
            [.ok, .workaround, .unofficial, .obsolete, .abandoned, .broken]
        #expect(ordered.map(\.severity) == [0, 1, 2, 3, 4, 5])
        #expect(ordered.max(by: { $0.severity < $1.severity }) == .broken)
    }

    /// **Les sept, en entier.** Ce que smapi.io a réellement rendu le
    /// 2026-08-25 pour les sept mods signalés du parc. Chacun doit livrer les
    /// trois choses qui rendent l'avertissement utile : un verdict, la version
    /// du jeu qui l'a cassé, et **au moins un lien** vers une sortie — sans
    /// quoi l'alerte ne ferait qu'inquiéter.
    @Test func theSevenRealVerdictsAllYieldSomethingActionable() throws {
        let cases: [(id: String, status: String, brokeIn: String, summary: String)] = [
        ("aedenthorn.TrainTracks", "Workaround", "Stardew Valley 1.6", "⚠ use [Train Tracks - Continued](https://www.nexusmods.com/stardewvalley/mods/28049) instead."),
        ("Slothsoft.Informant", "Workaround", "Stardew Valley 1.6", "⚠ use [unofficial update](https://forums.stardewvalley.net/threads/unofficial-mod-updates.2096/post-123243) or [Informant - The Tooltip Labels](https://www.nexusmods.com/stardewvalley/mods/21286) instead."),
        ("ZeroMeters.SAAT.Mod", "Unofficial", "Stardew Valley 1.6", "broken, use [unofficial version](https://forums.stardewvalley.net/threads/unofficial-mod-updates.2096/post-121255) (<small>1.1.3-unofficial.1-p1xel8ted</small>)."),
        ("ZeroMeters.SAAT.API", "Unofficial", "Stardew Valley 1.6", "broken, use [unofficial version](https://forums.stardewvalley.net/threads/unofficial-mod-updates.2096/post-121255) (<small>1.1.3-unofficial.1-p1xel8ted</small>)."),
        ("supert.adventureguildexpanded", "Unofficial", "Stardew Valley 1.6", "⚠ use [unofficial update](https://forums.stardewvalley.net/threads/unofficial-mod-updates.2096/post-126783) or [Adventurer's Guild Expanded - Unofficial Update for 1.6](https://www.nexusmods.com/stardewvalley/mods/22591)."),
        ("cat.modupdatemenu", "Unofficial", "Stardew Valley 1.5", "broken, use [unofficial version](https://forums.stardewvalley.net/threads/unofficial-mod-updates.2096/post-148313) (<small>1.6.1-unofficial-2.dphill</small>)."),
        ("hootless.BusLocations", "Unofficial", "Stardew Valley 1.6", "broken, use [unofficial version](https://github.com/Xytronix/BusLocations/releases) (<small>1.2.2-unofficial.1-Xytronix</small>)."),
        ]
        #expect(cases.count == 7)
        for entry in cases {
            let verdict = try #require(ModCompatibility.from(
                status: entry.status, brokeIn: entry.brokeIn, summary: entry.summary),
                "aucun verdict pour \(entry.id)")
            #expect(verdict.status.needsAttention, "\(entry.id) devrait demander une décision")
            #expect(verdict.brokeIn?.hasPrefix("Stardew Valley") == true, "\(entry.id)")
            #expect(!verdict.links.isEmpty, "\(entry.id) : aucune sortie proposée")
            // Plus aucun balisage ne doit rester sous les yeux de l'utilisateur.
            #expect(!verdict.summary.contains("]("), "\(entry.id) : lien Markdown resté brut")
            #expect(!verdict.summary.contains("<small>"), "\(entry.id) : balise restée brute")
            #expect(!verdict.summary.hasPrefix("⚠"), "\(entry.id) : avertissement en double")
        }
    }

    /// Un crochet qui n'ouvre pas un lien reste dans la phrase.
    @Test func aBracketThatIsNotALinkIsLeftAlone() {
        let parsed = ModCompatibility.parseSummary("broken [see notes] for 1.6")
        #expect(parsed.links.isEmpty)
        #expect(parsed.text == "broken [see notes] for 1.6")
    }
}
