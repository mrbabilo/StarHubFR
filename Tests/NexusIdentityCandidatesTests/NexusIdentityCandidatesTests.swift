import Testing
import Foundation
@testable import StarHubTHCore

/// Retrouver la page Nexus d'un mod qui n'en déclare aucune, à partir de son
/// seul nom. C'est la seconde moitié d'A3-T1 — la première, `NexusIdLearning`,
/// prend gratuitement ce que smapi.io sait déjà.
///
/// **Tout est mesuré sur les 83 mods du parc réel qui restent sans identifiant**
/// (2026-08-26, recherche GraphQL v2 réellement exécutée) :
///
/// - **55 ne rendent rien du tout.** Le mod a été retiré, renommé, ou n'a
///   jamais été sur Nexus. 20 de ces 55 sont des **composants de pack** dont le
///   nom n'a jamais été un titre Nexus — chercher « ARV- Maximum » ne peut pas
///   aboutir, c'est le pack « Always Raining in the Valley » qui a une page.
/// - **23 rendent des candidats, et 61 % de ces candidats sont des
///   traductions** : 45 sur 74. Le titre d'une traduction commence par celui du
///   mod, donc la comparaison par préfixe les attrape toutes. « LewdDew Valley »
///   rend neuf candidats dont neuf traductions ; « Fireworks Festival » sept
///   traductions et un seul vrai mod.
/// - Écarter le tag `Translation` fait passer les cas tranchés de 14 à
///   **18 candidats uniques**, et rend les cinq listes restantes lisibles.
///
/// L'auteur, lui, **confirme sans jamais trancher** : sur les 18, le pseudo
/// Nexus concorde 12 fois — parfois à une variante près (`skeleton` /
/// `Skeleton0w0`, `kurts` / `kurtsietz`), parfois pas du tout alors que c'est le
/// même mod (`Owljoy` / `OwlandJoy`). Il est donc affiché comme indice, jamais
/// utilisé comme filtre.
struct NexusIdentityCandidatesTests {

    private func hit(_ id: Int, _ name: String, uploader: String = "someone",
                     tags: [String] = [], days: Int = 0) -> NexusModSearch.Hit {
        NexusModSearch.Hit(modId: id, name: name, version: "1.0",
                           updatedAt: Date(timeIntervalSince1970: 1_700_000_000 - Double(days) * 86_400),
                           categoryName: "Misc", uploader: uploader,
                           adultContent: false, tags: tags)
    }

    @Test func translationsAreNeverCandidates() {
        // Cas réel : « Fireworks Festival », sept traductions pour un vrai mod.
        let hits = [
            hit(42347, "Fireworks Festival - Francais", tags: ["French", "Translation"]),
            hit(15616, "Fireworks Festival - Russian", tags: ["Translation"]),
            hit(19474, "Fireworks Festival----CHINESE", tags: ["Translation", "Chinese"]),
            hit(15261, "Fireworks Festival", uploader: "violetlizabet"),
        ]
        let found = NexusModSearch.identityCandidates(among: hits,
                                                      modName: "[CP] Fireworks Festival",
                                                      modAuthor: "violetlizabet")
        #expect(found.map(\.hit.modId) == [15261])
        #expect(found.first?.authorMatches == true)
    }

    @Test func aTitleThatDoesNotMatchIsNotACandidate() {
        // La recherche porte sur une sous-chaîne : elle rend des mods dont le
        // titre contient le terme sans désigner le même mod.
        let hits = [hit(1, "Something Else Entirely"), hit(2, "Secret Woods Warp")]
        let found = NexusModSearch.identityCandidates(among: hits,
                                                      modName: "Secret Woods Warp",
                                                      modAuthor: "jyxdong")
        #expect(found.map(\.hit.modId) == [2])
    }

    @Test func theAuthorConfirmsButNeverExcludes() {
        // Mesuré : `Owljoy` (manifeste) contre `OwlandJoy` (Nexus), le même mod.
        // Filtrer sur l'auteur perdrait le seul candidat juste.
        let hits = [hit(49790, "Owljoy Lunchboxes", uploader: "OwlandJoy")]
        let found = NexusModSearch.identityCandidates(among: hits,
                                                      modName: "Owljoy Lunchboxes",
                                                      modAuthor: "Owljoy")
        #expect(found.count == 1)
        #expect(found[0].authorMatches == false)
    }

    @Test func anAuthorVariantStillCounts() {
        // `skeleton` / `Skeleton0w0` et `kurts` / `kurtsietz` : le pseudo Nexus
        // prolonge celui du manifeste. Comparaison par préfixe, plancher à
        // quatre — sans quoi un « Max » confirmerait n'importe quoi.
        let hits = [hit(25929, "Growable Moss Extend", uploader: "Skeleton0w0")]
        let found = NexusModSearch.identityCandidates(among: hits,
                                                      modName: "[CP]Growable Moss Extend",
                                                      modAuthor: "skeleton")
        #expect(found[0].authorMatches == true)
    }

    @Test func oneAuthorAmongSeveralIsEnough() {
        // Cas réel : « StarAmy/Mila Stavetskaya », « Haze1nuts, 58 and Cara ».
        let hits = [hit(16886, "Mila's Traveling merchant Cart", uploader: "Stavetskaya")]
        let found = NexusModSearch.identityCandidates(among: hits,
                                                      modName: "Mila's Traveling Merchant",
                                                      modAuthor: "StarAmy/Mila Stavetskaya")
        #expect(found[0].authorMatches == true)
    }

    @Test func aConfirmedAuthorComesFirst() {
        // Mesuré : « Vanilla Forage Crops and Bushes » rend deux vrais mods,
        // dont un seul de l'auteur déclaré. C'est celui-là qu'on montre d'abord
        // — sans écarter l'autre, qui peut être une reprise légitime.
        let hits = [
            hit(39861, "Vanilla Forage Crops and Bushes Redux", uploader: "Chocoronron", days: 1),
            hit(25619, "Vanilla Forage Crops and Bushes", uploader: "ZoeyHoshi", days: 400),
        ]
        let found = NexusModSearch.identityCandidates(among: hits,
                                                      modName: "[AT] Vanilla Forage Crops and Bushes",
                                                      modAuthor: "ZoeyHoshi")
        #expect(found.map(\.hit.modId) == [25619, 39861])
    }

    @Test func anExactTitleBeatsALongerOneWhenNothingElseSeparatesThem() {
        // À auteur également inconnu, le titre qui *est* le nom vaut mieux que
        // celui qui ne fait que commencer par lui.
        let hits = [
            hit(1, "Storage Terminal Deluxe Edition", days: 1),
            hit(2, "Storage Terminal", days: 400),
        ]
        let found = NexusModSearch.identityCandidates(among: hits,
                                                      modName: "Storage Terminal",
                                                      modAuthor: "Victor")
        #expect(found.map(\.hit.modId) == [2, 1])
    }

    @Test func mostRecentFirstWhenNothingElseSeparatesThem() {
        let hits = [
            hit(1, "Smart Horse Rider", days: 400),
            hit(2, "Smart Horse Trainer", days: 1),
        ]
        let found = NexusModSearch.identityCandidates(among: hits,
                                                      modName: "Smart Horse",
                                                      modAuthor: "KhanhDang")
        #expect(found.map(\.hit.modId) == [2, 1])
    }

    @Test func nothingMatchesGivesNoCandidate() {
        // 55 des 83 mods mesurés sont dans ce cas — c'est le résultat le plus
        // fréquent, et il doit rester vide plutôt que d'offrir un à-peu-près.
        let hits = [hit(1, "Totally Unrelated Mod")]
        let found = NexusModSearch.identityCandidates(among: hits,
                                                      modName: "Console Commands",
                                                      modAuthor: "SMAPI")
        #expect(found.isEmpty)
    }

    @Test func aShortNameNeverMatchesAnything() {
        // Le plancher de quatre caractères de `namesMatch` vaut ici aussi :
        // un mod nommé « ARV » ne doit pas adopter le premier titre venu.
        let hits = [hit(1, "ARV Something Big")]
        let found = NexusModSearch.identityCandidates(among: hits,
                                                      modName: "ARV",
                                                      modAuthor: "Hime Tarts")
        #expect(found.isEmpty)
    }
}
