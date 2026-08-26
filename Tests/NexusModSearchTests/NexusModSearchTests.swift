import Testing
import Foundation
@testable import StarHubTHCore

struct NexusModSearchTests {
    private func body(_ name: String, gameId: Int = 1303, tag: String? = nil,
                      count: Int = 30) -> [String: Any] {
        let data = NexusModSearch.queryBody(name: name, gameId: gameId, tag: tag, count: count)!
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func variables(_ name: String) -> [String: Any] {
        body(name)["variables"] as? [String: Any] ?? [:]
    }

    // MARK: - Requête

    @Test func theQueryCarriesTheNameAndTheNumericGameId() {
        let vars = variables("Parchment")
        #expect(vars["name"] as? String == "Parchment")
        // Numérique, transmis en chaîne comme le veut le filtre : `gameDomainName`
        // seul rendait `totalCount: 0` sans la moindre erreur.
        #expect(vars["game"] as? String == "1303")
        #expect(vars["count"] as? Int == 30)
    }

    /// **Le piège mesuré.** L'index de Nexus ne connaît pas les accents :
    /// « Français » rend 0 résultat là où « Francais » en rend 184. Un nom de
    /// mod accentué chercherait dans le vide, sans erreur pour le dire.
    @Test func accentsAreFoldedBeforeSearching() {
        #expect(NexusModSearch.searchTerm(for: "Français") == "Francais")
        #expect(NexusModSearch.searchTerm(for: "Élégant Café") == "Elegant Cafe")
        #expect(variables("Traduction Française")["name"] as? String == "Traduction Francaise")
    }

    @Test func theTermIsTrimmed() {
        #expect(NexusModSearch.searchTerm(for: "  Parchment \n") == "Parchment")
    }

    @Test func anEmptyNameProducesNoQueryAtAll() {
        #expect(NexusModSearch.queryBody(name: "", gameId: 1303) == nil)
        #expect(NexusModSearch.queryBody(name: "   ", gameId: 1303) == nil)
    }

    @Test func theQuerySortsByMostRecentlyUpdated() {
        let query = body("Parchment")["query"] as? String ?? ""
        #expect(query.contains("updatedAt"))
        #expect(query.contains("DESC"))
        // `op: WILDCARD` est la seule opération de nom que le schéma accepte —
        // `MATCHES` est refusé.
        #expect(query.contains("WILDCARD"))
    }

    /// **Le chemin principal.** Nexus pose un tag `French` sur ses traductions
    /// françaises — 77 sur 80 mesurées le portent — et filtrer dessus laisse le
    /// tri au serveur : sur « Parchment », « nom + tag » rend exactement la
    /// bonne, là où le nom seul en rendait douze toutes langues confondues.
    @Test func theTagFilterEntersBothTheQueryAndTheVariables() {
        let payload = body("Parchment", tag: NexusModSearch.frenchTag)
        let query = payload["query"] as? String ?? ""
        #expect(query.contains("tag: { value: $tag, op: EQUALS }"))
        #expect(query.contains("$tag: String!"))
        #expect((payload["variables"] as? [String: Any])?["tag"] as? String == "French")
    }

    /// Sans tag demandé, la requête n'en parle pas du tout : un `tag` vide
    /// rendrait `totalCount: 0` sans erreur, comme le domaine du jeu employé à
    /// la place de son identifiant.
    @Test func noTagMeansNoTagFilterAtAll() {
        let payload = body("Parchment")
        let query = payload["query"] as? String ?? ""
        // Le **filtre**, pas le mot : les nœuds demandent `tags { name }` en
        // permanence — c'est ce champ qui sépare un supplément d'une traduction.
        #expect(!query.contains("tag: {"))
        #expect(!query.contains("$tag: String!"))
        #expect((payload["variables"] as? [String: Any])?["tag"] == nil)
    }

    // MARK: - Réponse

    /// La forme réelle d'une réponse, relevée sur l'API le 2026-08-25.
    private let liveResponse = """
    {"data":{"mods":{"totalCount":12,"nodes":[
      {"modId":50233,"name":"Parchment - Fishing Log - Francais","version":"1.1.0",
       "updatedAt":"2026-08-09T17:33:00Z","adultContent":false,"status":"published",
       "modCategory":{"name":"User Interface"},"uploader":{"name":"Deovos"}},
      {"modId":49525,"name":"Parchment","version":"1.2.3",
       "updatedAt":"2026-08-08T02:58:49Z","adultContent":false,"status":"published",
       "modCategory":{"name":"User Interface"},"uploader":{"name":"Elliaria"}}
    ]}}}
    """.data(using: .utf8)!

    @Test func aLiveResponseIsRead() throws {
        let hits = try NexusModSearch.decode(liveResponse).get().hits
        #expect(hits.count == 2)
        #expect(hits[0].modId == 50233)
        #expect(hits[0].name == "Parchment - Fishing Log - Francais")
        #expect(hits[0].version == "1.1.0")
        #expect(hits[0].uploader == "Deovos")
        #expect(hits[0].categoryName == "User Interface")
        #expect(hits[0].updatedAt == NexusModSearch.parseDate("2026-08-09T17:33:00Z"))
    }

    /// **GraphQL rend 200 avec un tableau `errors`.** Prendre ça pour un
    /// résultat vide changerait une panne de schéma en « aucune traduction
    /// trouvée » — exactement le genre de réponse fausse qu'une dépendance non
    /// documentée doit interdire.
    @Test func graphQLErrorsAreAFailureEvenOnASuccessfulStatus() {
        let payload = """
        {"errors":[{"message":"Field 'mods' doesn't accept argument 'first'"}],"data":null}
        """.data(using: .utf8)!
        #expect(NexusModSearch.decode(payload) == .failure(.service("Field 'mods' doesn't accept argument 'first'")))
    }

    /// Des données **et** des erreurs : la panne l'emporte, une réponse
    /// partielle n'est pas un résultat.
    @Test func partialDataWithErrorsIsStillAFailure() {
        let payload = """
        {"errors":[{"message":"boom"}],"data":{"mods":{"nodes":[{"modId":1,"name":"X"}]}}}
        """.data(using: .utf8)!
        #expect(NexusModSearch.decode(payload) == .failure(.service("boom")))
    }

    @Test func somethingThatIsNotJsonIsMalformed() {
        #expect(NexusModSearch.decode(Data("<html>503</html>".utf8)) == .failure(.malformed))
    }

    @Test func aJsonOfTheWrongShapeIsMalformed() {
        #expect(NexusModSearch.decode(Data("{\"data\":{}}".utf8)) == .failure(.malformed))
    }

    @Test func noResultIsAnEmptySuccessNotAFailure() throws {
        let payload = Data("{\"data\":{\"mods\":{\"totalCount\":0,\"nodes\":[]}}}".utf8)
        #expect(try NexusModSearch.decode(payload).get().hits.isEmpty)
    }

    /// Un mod retiré ou en brouillon ne se télécharge pas : le proposer
    /// enverrait sur une page morte.
    @Test func unpublishedModsAreLeftOut() throws {
        let payload = """
        {"data":{"mods":{"nodes":[
          {"modId":1,"name":"Published","status":"published"},
          {"modId":2,"name":"Hidden","status":"hidden"},
          {"modId":3,"name":"Sans statut"}
        ]}}}
        """.data(using: .utf8)!
        let hits = try NexusModSearch.decode(payload).get().hits
        #expect(hits.map(\.modId) == [1, 3])
    }

    @Test func aMissingIdentifierDropsTheRowRatherThanTheWholeAnswer() throws {
        let payload = """
        {"data":{"mods":{"nodes":[
          {"name":"Sans identifiant"},
          {"modId":7,"name":"Bon"}
        ]}}}
        """.data(using: .utf8)!
        #expect(try NexusModSearch.decode(payload).get().hits.map(\.modId) == [7])
    }

    /// Le champ arrive en nombre aujourd'hui ; une chaîne ne doit pas faire
    /// disparaître le résultat en silence.
    @Test func aStringIdentifierIsAccepted() throws {
        let payload = Data("{\"data\":{\"mods\":{\"nodes\":[{\"modId\":\"42\",\"name\":\"X\"}]}}}".utf8)
        #expect(try NexusModSearch.decode(payload).get().hits.first?.modId == 42)
    }

    @Test func anUnreadableDateLeavesTheRestOfTheRowIntact() throws {
        let payload = """
        {"data":{"mods":{"nodes":[{"modId":9,"name":"X","updatedAt":"hier"}]}}}
        """.data(using: .utf8)!
        let hit = try #require(try NexusModSearch.decode(payload).get().hits.first)
        #expect(hit.updatedAt == nil)
        #expect(hit.name == "X")
    }

    /// **Le total, pas seulement la page.** La requête plafonne à 30 résultats
    /// et l'écran en montre moins ; sans ce chiffre, une recherche qui rend 428
    /// mods paraîtrait en rendre six.
    @Test func theTotalIsKeptNotJustThePage() throws {
        let page = try NexusModSearch.decode(liveResponse).get()
        #expect(page.totalCount == 12)
    }

    /// Un `totalCount` absent ne vaut pas zéro : sinon la fiche annoncerait
    /// « aucun résultat » en en affichant un.
    @Test func aMissingTotalFallsBackOnWhatArrived() throws {
        let payload = Data("{\"data\":{\"mods\":{\"nodes\":[{\"modId\":1,\"name\":\"X\"}]}}}".utf8)
        #expect(try NexusModSearch.decode(payload).get().totalCount == 1)
    }

    // MARK: - Reconnaître une traduction française

    /// Titres réels relevés sur Nexus le 2026-08-25.
    @Test func realFrenchTitlesAreRecognised() {
        for title in ["Parchment - Fishing Log - Francais",
                      "Stardew Valley Expanded -  Francais",
                      "UI Info Suite 2 - Francais",
                      "Traduction française de Ridgeside Village",
                      "Sword and Sorcery FR",
                      "Cornucopia - VF",
                      "Better Chests - French Translation"] {
            #expect(NexusModSearch.announcesFrenchTranslation(title), "\(title)")
        }
    }

    /// Les autres langues n'ont pas besoin d'être écartées à part : il leur
    /// suffit de ne porter aucun marqueur français. Titres réels, tirés des
    /// douze résultats de « Parchment ».
    @Test func otherLanguagesCarryNoFrenchMarker() {
        for title in ["Parchment - Fishing Log (Russian Translation)",
                      "Parchment - Fishing Log_JP",
                      "Parchment - Fishing Log 1.2.3 (Thai Translate)",
                      "Parchment - Fishing Log-Spanish Translation",
                      "Parchment - Fishing Log - Vietnamese Translation",
                      "Parchment - Fishing Log-KOR Translation",
                      "Parchment - Fishing Log PT-BR",
                      "Parchment"] {
            #expect(!NexusModSearch.announcesFrenchTranslation(title), "\(title)")
        }
    }

    /// **Mots entiers, jamais des fragments.** « fr » contenu dans « from »,
    /// « fresh » ou « Frontier » ferait passer pour françaises la moitié des
    /// pages de Nexus — le mot-clé « FR » seul rend 1 559 mods sur Stardew, là
    /// où « Francais » en rend 184.
    @Test func aFragmentIsNotAMarker() {
        for title in ["Fresh Fish", "From the Frontier", "Fruit Trees Redux",
                      "Africa Map", "Refreshed UI"] {
            #expect(!NexusModSearch.announcesFrenchTranslation(title), "\(title)")
        }
    }

    /// « PT-BR » se découpe en « pt » et « br » : la césure sur tout ce qui
    /// n'est ni lettre ni chiffre est ce qui empêche « br » de devenir « fr »
    /// par glissement, et « Log_JP » de rester un seul mot.
    @Test func titlesAreCutOnEveryNonAlphanumeric() {
        #expect(NexusModSearch.words(in: "Log_JP - PT/BR") == ["log", "jp", "pt", "br"])
    }

    @Test func markersAreFoundWhateverTheAccentOrTheCase() {
        #expect(NexusModSearch.announcesFrenchTranslation("Mod — FRANÇAIS"))
        #expect(NexusModSearch.announcesFrenchTranslation("mod francaise"))
    }

    /// Parmi douze résultats réels, la seule traduction française — et le mod
    /// hôte lui-même reste dehors.
    @Test func onlyFrenchTranslationsAreKept() {
        let hits = ["Parchment - Fishing Log - Francais",
                    "Parchment - Fishing Log (Russian Translation)",
                    "Parchment"].enumerated().map { index, name in
            NexusModSearch.Hit(modId: index, name: name, version: "1", updatedAt: nil,
                               categoryName: "", uploader: "", adultContent: false)
        }
        #expect(NexusModSearch.frenchTranslations(among: hits).map(\.name)
                == ["Parchment - Fishing Log - Francais"])
    }

    /// La plus récemment mise à jour en tête : c'est celle qu'on veut.
    @Test func frenchTranslationsComeMostRecentFirst() {
        func hit(_ id: Int, _ day: Int) -> NexusModSearch.Hit {
            NexusModSearch.Hit(modId: id, name: "Mod - Francais", version: "1",
                               updatedAt: Date(timeIntervalSince1970: TimeInterval(day) * 86400),
                               categoryName: "", uploader: "", adultContent: false)
        }
        #expect(NexusModSearch.frenchTranslations(among: [hit(1, 10), hit(2, 30), hit(3, 20)])
                .map(\.modId) == [2, 3, 1])
    }

    /// Une traduction sans date connue ne doit pas passer devant une datée.
    @Test func anUndatedTranslationSinksToTheBottom() {
        let dated = NexusModSearch.Hit(modId: 1, name: "Mod FR", version: "1",
                                       updatedAt: Date(timeIntervalSince1970: 1000),
                                       categoryName: "", uploader: "", adultContent: false)
        let undated = NexusModSearch.Hit(modId: 2, name: "Mod VF", version: "1", updatedAt: nil,
                                         categoryName: "", uploader: "", adultContent: false)
        #expect(NexusModSearch.frenchTranslations(among: [undated, dated]).map(\.modId) == [1, 2])
    }

    // MARK: - Préfixes de convention

    /// **Le faux négatif muet.** La recherche porte sur une sous-chaîne : le
    /// `[CP]` d'un manifeste, qui n'appartient à aucun titre Nexus, la faisait
    /// échouer entièrement — mesuré, 0 résultat contre 9 sans lui — et la fiche
    /// annonçait « aucune traduction trouvée ». 148 manifestes sur 995 en
    /// portent un.
    @Test func aConventionPrefixIsNotSearchedFor() {
        #expect(NexusModSearch.searchTerm(for: "[CP] Make Gunther Real") == "Make Gunther Real")
        #expect(NexusModSearch.searchTerm(for: "(TTG) Mapster - A Local Map Mod")
                == "Mapster - A Local Map Mod")
        #expect(NexusModSearch.searchTerm(for: "[FTM] Wildflour's Atelier Goods")
                == "Wildflour's Atelier Goods")
    }

    /// Plusieurs cadres empilés, et les accents repliés dans la foulée.
    @Test func severalPrefixesGoAndAccentsStillFold() {
        #expect(NexusModSearch.searchTerm(for: "[CP] [FR] Forêt Enchantée")
                == "Foret Enchantee")
    }

    /// Ce qui n'est pas un préfixe de cadre reste : une parenthèse de fin
    /// appartient au titre, et un texte long entre crochets n'est pas un cadre.
    @Test func whatIsNotAFrameworkPrefixStays() {
        #expect(NexusModSearch.searchTerm(for: "Sword and Sorcery (Traduction francaise - FR)")
                == "Sword and Sorcery (Traduction francaise - FR)")
        #expect(NexusModSearch.searchTerm(for: "[A Very Long Bracket] Mod")
                == "[A Very Long Bracket] Mod")
    }

    /// **Ne jamais rendre le vide** : un nom fait de son seul préfixe vaut
    /// mieux cherché tel quel que pas cherché du tout.
    @Test func aNameMadeOnlyOfItsPrefixIsKept() {
        #expect(NexusModSearch.searchTerm(for: "[CP]") == "[CP]")
        #expect(NexusModSearch.queryBody(name: "[CP]", gameId: 1303) != nil)
    }

    // MARK: - Résultats déjà tagués par le serveur

    /// **Le tag suffit.** Une traduction correctement taguée `French` dont le
    /// titre ne dit rien était jetée par le filtre de titre : la fiche
    /// annonçait qu'aucune traduction n'existait alors que Nexus venait de la
    /// rendre.
    @Test func aTaggedTranslationSurvivesASilentTitle() {
        func hit(_ id: Int, _ name: String, _ day: Int) -> NexusModSearch.Hit {
            NexusModSearch.Hit(modId: id, name: name, version: "1",
                               updatedAt: Date(timeIntervalSince1970: TimeInterval(day) * 86400),
                               categoryName: "", uploader: "", adultContent: false)
        }
        let hits = [hit(1, "Parchment Traduction", 10), hit(2, "Parchment", 30)]
        #expect(NexusModSearch.ranked(hits).map(\.modId) == [1, 2])
    }

    /// Le titre classe : à égalité de marqueur, la plus récente devant.
    @Test func rankedFallsBackOnRecency() {
        func hit(_ id: Int, _ day: Int) -> NexusModSearch.Hit {
            NexusModSearch.Hit(modId: id, name: "Mod FR", version: "1",
                               updatedAt: Date(timeIntervalSince1970: TimeInterval(day) * 86400),
                               categoryName: "", uploader: "", adultContent: false)
        }
        #expect(NexusModSearch.ranked([hit(1, 10), hit(2, 30)]).map(\.modId) == [2, 1])
    }

    /// Un mod français n'est pas sa propre traduction.
    @Test func theHostModIsNeverProposedAsItsOwnTranslation() {
        let host = NexusModSearch.Hit(modId: 42, name: "Mod Francais", version: "1",
                                      updatedAt: nil, categoryName: "", uploader: "",
                                      adultContent: false)
        #expect(NexusModSearch.ranked([host], excluding: 42).isEmpty)
        #expect(NexusModSearch.frenchTranslations(among: [host], excluding: 42).isEmpty)
    }

    // MARK: - Suppléments

    private func hit(_ id: Int, _ name: String, tags: [String] = [],
                     day: Int = 0) -> NexusModSearch.Hit {
        NexusModSearch.Hit(modId: id, name: name, version: "1",
                           updatedAt: Date(timeIntervalSince1970: TimeInterval(day) * 86400),
                           categoryName: "", uploader: "", adultContent: false, tags: tags)
    }

    /// **Le tag `Translation` est le seul signal qui les sépare.** Mesuré sur
    /// douze résultats « Wildflour » : les six traductions le portent toutes,
    /// les deux vrais suppléments aucun. Le titre ne dit rien — « (ES-LATAM) … »
    /// n'annonce pas plus une traduction que « Item Bags for … » une greffe.
    @Test func translationsAreTheNoiseToRemove() {
        let hits = [
            hit(1, "Chinese translation-Wildflour's Atelier Goods", tags: ["Translation"], day: 5),
            hit(2, "Item Bags for Wildflour's Atelier Goods", day: 3),
            hit(3, "(ES-LATAM) Wildflour's Atelier Goods", tags: ["Translation", "SMAPI"], day: 4),
            hit(4, "Domed Pots compatibility for Wildflour's Mod's", day: 1),
        ]
        #expect(NexusModSearch.supplements(among: hits).map(\.modId) == [2, 4])
    }

    /// Un mod n'est pas son propre supplément.
    @Test func theHostIsNotItsOwnSupplement() {
        let hits = [hit(42, "Wildflour's Atelier Goods"), hit(7, "Item Bags for Wildflour's")]
        #expect(NexusModSearch.supplements(among: hits, excluding: 42).map(\.modId) == [7])
    }

    /// **Le filet qui compte** : 111 mods du parc ne déclarent aucun
    /// identifiant Nexus. Sans exclusion par le titre, le mod figurerait en
    /// tête de ses propres suppléments — vu en simulant la recherche sur
    /// « Wildflour's Atelier Goods ».
    @Test func theHostIsExcludedByTitleWhenItHasNoNexusId() {
        let hits = [hit(1, "Wildflour's Atelier Goods"),
                    hit(2, "Item Bags for Wildflour's Atelier Goods")]
        #expect(NexusModSearch.supplements(among: hits,
                                           hostName: "[FTM] Wildflour's Atelier Goods")
                .map(\.modId) == [2])
    }

    /// Un titre qui **ajoute** quelque chose reste : c'est justement la forme
    /// d'un supplément.
    @Test func aTitleThatAddsSomethingIsKept() {
        let hits = [hit(1, "Wildflour's Atelier Goods - An Artisan Goods Expansion")]
        #expect(NexusModSearch.supplements(among: hits, hostName: "Wildflour's Atelier Goods")
                .count == 1)
    }

    /// Le tag est comparé sans égard à la casse : les auteurs l'écrivent comme
    /// ils veulent, et un `translation` minuscule laisserait passer le bruit.
    @Test func theTranslationTagIsMatchedIgnoringCase() {
        #expect(NexusModSearch.supplements(among: [hit(1, "X", tags: ["translation"])]).isEmpty)
        #expect(NexusModSearch.supplements(among: [hit(1, "X", tags: ["TRANSLATION"])]).isEmpty)
    }

    /// Sans tag, rien n'est écarté : un mod que Nexus ne tague pas reste un
    /// candidat, c'est à l'utilisateur de juger sur le titre.
    @Test func anUntaggedHitSurvives() {
        #expect(NexusModSearch.supplements(among: [hit(1, "Whipped Cream for Cornucopia")])
                .map(\.modId) == [1])
    }

    @Test func fractionalSecondsAreAlsoParsed() {
        #expect(NexusModSearch.parseDate("2026-08-09T17:33:00.500Z") != nil)
        #expect(NexusModSearch.parseDate("pas une date") == nil)
    }
}
