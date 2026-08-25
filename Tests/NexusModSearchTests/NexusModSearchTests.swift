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
        #expect(!query.contains("tag"))
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
        let hits = try NexusModSearch.decode(liveResponse).get()
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
        #expect(try NexusModSearch.decode(payload).get().isEmpty)
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
        let hits = try NexusModSearch.decode(payload).get()
        #expect(hits.map(\.modId) == [1, 3])
    }

    @Test func aMissingIdentifierDropsTheRowRatherThanTheWholeAnswer() throws {
        let payload = """
        {"data":{"mods":{"nodes":[
          {"name":"Sans identifiant"},
          {"modId":7,"name":"Bon"}
        ]}}}
        """.data(using: .utf8)!
        #expect(try NexusModSearch.decode(payload).get().map(\.modId) == [7])
    }

    /// Le champ arrive en nombre aujourd'hui ; une chaîne ne doit pas faire
    /// disparaître le résultat en silence.
    @Test func aStringIdentifierIsAccepted() throws {
        let payload = Data("{\"data\":{\"mods\":{\"nodes\":[{\"modId\":\"42\",\"name\":\"X\"}]}}}".utf8)
        #expect(try NexusModSearch.decode(payload).get().first?.modId == 42)
    }

    @Test func anUnreadableDateLeavesTheRestOfTheRowIntact() throws {
        let payload = """
        {"data":{"mods":{"nodes":[{"modId":9,"name":"X","updatedAt":"hier"}]}}}
        """.data(using: .utf8)!
        let hit = try #require(try NexusModSearch.decode(payload).get().first)
        #expect(hit.updatedAt == nil)
        #expect(hit.name == "X")
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

    @Test func fractionalSecondsAreAlsoParsed() {
        #expect(NexusModSearch.parseDate("2026-08-09T17:33:00.500Z") != nil)
        #expect(NexusModSearch.parseDate("pas une date") == nil)
    }
}
