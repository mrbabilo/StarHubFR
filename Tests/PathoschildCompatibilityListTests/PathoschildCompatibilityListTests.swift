import Testing
import Foundation
@testable import StarHubTHCore

/// Tests pour le filet Pathoschild (A2-T3) :
/// - strip des commentaires JSONC (`//` ligne, `/* bloc */`) ;
/// - décodage des entrées utiles (`id`, `status`, `brokeIn`, `summary`) ;
/// - jointure sur `UniqueID` vers `ModCompatibility` ;
/// - tolérance au payload vide / malformé.
struct PathoschildCompatibilityListTests {

    // MARK: - Strip des commentaires JSONC

    @Test func stripsLineComments() {
        let raw = """
        {
          // this is a comment
          "mods": []
        }
        """
        let cleaned = PathoschildCompatibilityList.stripJSONComments(raw)
        #expect(!cleaned.contains("// this is a comment"))
        #expect(cleaned.contains("\"mods\""))
    }

    @Test func stripsBlockComments() {
        let raw = """
        {
          /* one liner */
          "mods": [
            /* multi
               line */
            {"id": "x", "status": "broken"}
          ]
        }
        """
        let cleaned = PathoschildCompatibilityList.stripJSONComments(raw)
        #expect(!cleaned.contains("/*"))
        #expect(cleaned.contains("\"id\": \"x\""))
    }

    @Test func preservesStringsThatLookLikeComments() {
        // Le strip est **string-aware** : un `//` à l'intérieur d'une
        // chaîne n'est pas traité comme un commentaire. Sans cette garde,
        // le résumé « use [Z](https://example.com) instead. » perdait son
        // URL — et c'est précisément ce qu'un dump Pathoschild porte.
        let raw = #"{"url": "https://example.com/path"}"#
        let cleaned = PathoschildCompatibilityList.stripJSONComments(raw)
        #expect(cleaned.contains("https://example.com/path"))
    }

    @Test func escapedQuotesInsideStringsDoNotBreakStringTracking() {
        // `\"` ne ferme pas la chaîne — sans quoi le `"` suivant serait
        // pris pour une ouverture de chaîne et tout le reste serait
        // charcuté.
        let raw = #"{ "summary": "say \"hi\" then // not a comment" }"#
        let cleaned = PathoschildCompatibilityList.stripJSONComments(raw)
        #expect(cleaned.contains("say \\\"hi\\\" then // not a comment"))
    }

    // MARK: - Décodage

    @Test func decodesTheSevenFieldsItCaresAbout() throws {
        let raw = """
        {
          "$schema": "schema.json",
          "mods": [
            { "name": "X", "author": "Y", "id": "x.y", "nexus": 1, "github": null,
              "status": "broken", "brokeIn": "Stardew Valley 1.6",
              "summary": "use [Z](https://example.com) instead." },
            { "name": "A", "author": "B", "id": "a.b", "nexus": 2,
              "status": "abandoned" },
            { "name": "C", "author": "D", "id": "c.d" }
          ]
        }
        """
        let entries = try #require(PathoschildCompatibilityList.decode(Data(raw.utf8)))
        #expect(entries.count == 3)
        let first = try #require(entries.first { $0.id == "x.y" })
        #expect(first.status == "broken")
        #expect(first.brokeIn == "Stardew Valley 1.6")
        #expect(first.summary?.contains("[Z]") == true)
    }

    @Test func decodesBlockCommentsAnywhere() throws {
        let raw = """
        { "mods": [
            /* a doc comment */
            { "id": "x.y", "status": "broken"
              /* inline note */
            }
        ] }
        """
        let entries = try #require(PathoschildCompatibilityList.decode(Data(raw.utf8)))
        #expect(entries.count == 1)
        #expect(entries.first?.status == "broken")
    }

    @Test func decodeToleratesEmptyAndMalformedPayload() {
        #expect(PathoschildCompatibilityList.decode(Data("".utf8)) == nil)
        #expect(PathoschildCompatibilityList.decode(Data("not json".utf8)) == nil)
        #expect(PathoschildCompatibilityList.decode(Data("[]".utf8)) == nil)
        #expect(PathoschildCompatibilityList.decode(Data(#"{"mods": "wrong shape"}"#.utf8)) == nil)
    }

    @Test func decodeDropsEntriesWithNoId() {
        let raw = """
        { "mods": [
          { "status": "broken" },
          { "id": "", "status": "broken" },
          { "id": "ok.mod", "status": "broken" }
        ]}
        """
        let entries = PathoschildCompatibilityList.decode(Data(raw.utf8)) ?? []
        #expect(entries.count == 1)
        #expect(entries.first?.id == "ok.mod")
    }

    // MARK: - Jointure

    @Test func joinProducesModCompatibilityForMatchingUniqueIds() throws {
        let entries = [
            PathoschildCompatibilityList.Entry(
                id: "aedenthorn.TrainTracks",
                status: "Workaround",
                brokeIn: "Stardew Valley 1.6",
                summary: "⚠ use [Train Tracks - Continued](https://www.nexusmods.com/stardewvalley/mods/28049) instead.",
                nexusID: nil),
            PathoschildCompatibilityList.Entry(
                id: "ZeroMeters.SAAT.Mod",
                status: "Unofficial",
                brokeIn: "Stardew Valley 1.6",
                summary: nil,
                nexusID: nil)
        ]
        let verdicts = PathoschildCompatibilityList.verdicts(
            for: ["aedenthorn.TrainTracks", "ZeroMeters.SAAT.Mod", "unknown.mod"],
            from: entries
        )
        #expect(verdicts.count == 2)
        let train = try #require(verdicts["aedenthorn.TrainTracks"])
        #expect(train.status == .workaround)
        #expect(train.brokeIn == "Stardew Valley 1.6")
        let saat = try #require(verdicts["ZeroMeters.SAAT.Mod"])
        #expect(saat.status == .unofficial)
    }

    @Test func joinIgnoresEmptyUniqueIdsAndEntriesWithoutStatus() {
        let entries = [
            PathoschildCompatibilityList.Entry(id: "x.y", status: nil, brokeIn: nil, summary: nil, nexusID: nil),
            PathoschildCompatibilityList.Entry(id: "a.b", status: "Ok", brokeIn: nil, summary: nil, nexusID: nil)
        ]
        let verdicts = PathoschildCompatibilityList.verdicts(
            for: ["", "x.y", "a.b"], from: entries)
        // `Ok` est retenu (voir ModCompatibility.from) ; un statut absent n'est pas un verdict.
        #expect(verdicts.keys.sorted() == ["a.b"])
        #expect(verdicts["a.b"]?.status == .ok)
    }

    @Test func joinReturnsEmptyWhenNoOverlap() {
        let entries = [PathoschildCompatibilityList.Entry(
            id: "x.y", status: "broken", brokeIn: nil, summary: nil, nexusID: nil)]
        #expect(PathoschildCompatibilityList.verdicts(for: ["other"], from: entries).isEmpty)
        #expect(PathoschildCompatibilityList.verdicts(for: [], from: entries).isEmpty)
    }

    @Test func unknownStatusIsSkipped() {
        // Cohérent avec `ModCompatibility.from` : un statut que le code ne
        // connaît pas ne devient pas « sain » par défaut.
        let entries = [PathoschildCompatibilityList.Entry(
            id: "x.y", status: "Sideways", brokeIn: nil, summary: nil, nexusID: nil)]
        let verdicts = PathoschildCompatibilityList.verdicts(for: ["x.y"], from: entries)
        #expect(verdicts.isEmpty)
    }

    // MARK: - Mise à jour non officielle sans statut

    // Mesuré sur le dump réel du 2026-09-04 (4 720 entrées) : **67 portent un
    // `unofficialUpdate`, et 63 d'entre elles n'ont aucun `status`** — 62 n'ont
    // pas non plus de `summary`. Elles ne produisaient donc aucun verdict,
    // quand smapi.io, interrogé le même jour sur les mêmes identifiants, les
    // déclare `Unofficial` avec « broken, use unofficial version ».
    // Sur le parc : **4 mods** (Bus Locations, Mod Update Menu, SAAT ×2) que le
    // filet passait sous silence dès que smapi.io se taisait.

    @Test func anUnofficialUpdateWithoutStatusBecomesAnUnofficialVerdict() throws {
        let entries = [PathoschildCompatibilityList.Entry(
            id: "hootless.BusLocations",
            status: nil,
            brokeIn: "Stardew Valley 1.6",
            summary: nil,
            nexusID: 21264,
            unofficialUpdate: .init(version: "1.2.2-unofficial.1-Xytronix",
                                    url: "https://github.com/Xytronix/BusLocations/releases"))]
        let verdict = try #require(PathoschildCompatibilityList.verdicts(
            for: ["hootless.BusLocations"], from: entries)["hootless.BusLocations"])
        #expect(verdict.status == .unofficial)
        // `brokeIn` est porté : c'est lui qui fait « cassé depuis la 1.6 »
        // plutôt que « une mise à jour existe ».
        #expect(verdict.brokeIn == "Stardew Valley 1.6")
        // Aucune phrase n'est inventée — le dump n'en a pas, et une phrase
        // écrite en dur ici ne serait traduite nulle part.
        #expect(verdict.summary.isEmpty)
        // Le lien porte le **numéro de version** pour libellé : c'est ce qu'il
        // faut installer, et l'UI en fait un bouton.
        #expect(verdict.links.count == 1)
        #expect(verdict.links.first?.label == "1.2.2-unofficial.1-Xytronix")
        #expect(verdict.links.first?.url == "https://github.com/Xytronix/BusLocations/releases")
    }

    @Test func anExistingStatusIsNeverOverwrittenByTheInference() throws {
        // Le voisin qui ne doit **pas** être inféré. Quatre des 67 entrées
        // portent déjà un statut (3 `workaround`, 1 `abandoned`) : les faire
        // passer pour « une mise à jour non officielle existe » perdrait plus
        // que l'inférence ne gagne — `abandoned` est le verdict le plus grave
        // des deux, et il dit qu'aucun remplaçant n'est proposé.
        let entries = [
            PathoschildCompatibilityList.Entry(
                id: "a.abandoned", status: "Abandoned", brokeIn: "SMAPI 3.0",
                summary: nil, nexusID: nil,
                unofficialUpdate: .init(version: "1.0.1-unofficial.1", url: "https://example.com/a")),
            PathoschildCompatibilityList.Entry(
                id: "b.workaround", status: "Workaround", brokeIn: nil,
                summary: nil, nexusID: nil,
                unofficialUpdate: .init(version: "2.0.0-unofficial.1", url: "https://example.com/b"))
        ]
        let verdicts = PathoschildCompatibilityList.verdicts(
            for: ["a.abandoned", "b.workaround"], from: entries)
        #expect(try #require(verdicts["a.abandoned"]).status == .abandoned)
        #expect(try #require(verdicts["b.workaround"]).status == .workaround)
    }

    @Test func anUnknownStatusIsStillSkippedEvenWithAnUnofficialUpdate() {
        // L'inférence ne comble que l'**absence** de statut. Un statut que le
        // code ne connaît pas garde sa règle : `nil`, jamais une valeur de
        // repli — smapi.io peut en ajouter un demain.
        let entries = [PathoschildCompatibilityList.Entry(
            id: "x.y", status: "Sideways", brokeIn: nil, summary: nil, nexusID: nil,
            unofficialUpdate: .init(version: "1.0.0-unofficial.1", url: "https://example.com/x"))]
        #expect(PathoschildCompatibilityList.verdicts(for: ["x.y"], from: entries).isEmpty)
    }

    @Test func noStatusAndNoUnofficialUpdateStillProducesNothing() {
        // L'inférence n'invente pas un verdict à partir du seul `brokeIn` :
        // 1 109 entrées du dump en portent un pour 534 statuts, et « cassé
        // par SMAPI 3.0 » ne dit rien d'un mod réparé depuis.
        let entries = [PathoschildCompatibilityList.Entry(
            id: "x.y", status: nil, brokeIn: "SMAPI 3.0", summary: nil, nexusID: nil)]
        #expect(PathoschildCompatibilityList.verdicts(for: ["x.y"], from: entries).isEmpty)
    }

    @Test func theUnofficialLinkIsNotAddedTwiceWhenTheSummaryAlreadyCarriesIt() throws {
        // **Une seule** des 63 entrées sans statut porte un `summary` —
        // `Lajna.24hClock` — et ce résumé cite déjà l'URL de son
        // `unofficialUpdate`, plus un mod de remplacement. Un troisième bouton
        // vers la première page serait du bruit, et l'UI n'en affiche que deux :
        // il chasserait le remplaçant de l'écran.
        let entries = [PathoschildCompatibilityList.Entry(
            id: "Lajna.24hClock", status: nil, brokeIn: "SMAPI 3.0",
            summary: "use [unofficial update](https://forums.example.net/post-3342641)"
                   + " or [24H Clock Language](https://www.nexusmods.com/stardewvalley/mods/20794)"
                   + " instead.",
            nexusID: nil,
            unofficialUpdate: .init(version: "1.0.1-unofficial.1-pathoschild",
                                    url: "https://forums.example.net/post-3342641"))]
        let verdict = try #require(PathoschildCompatibilityList.verdicts(
            for: ["Lajna.24hClock"], from: entries)["Lajna.24hClock"])
        #expect(verdict.status == .unofficial)
        #expect(verdict.links.map(\.url) == ["https://forums.example.net/post-3342641",
                                            "https://www.nexusmods.com/stardewvalley/mods/20794"])
        #expect(verdict.summary == "use unofficial update or 24H Clock Language instead.")
    }

    @Test func theUnofficialUpdateIsDecodedFromTheDump() throws {
        // Forme réelle du champ : un objet `{ version, url }`, jamais une
        // chaîne — vérifié sur les 67 entrées du dump.
        let raw = """
        {
          "mods": [
            {
              "id": "cat.modupdatemenu",
              "brokeIn": "Stardew Valley 1.5",
              "unofficialUpdate": {
                "version": "1.6.1-unofficial-2.dphill",
                "url": "https://forums.example.net/post-148313"
              }
            }
          ]
        }
        """
        let entries = try #require(PathoschildCompatibilityList.decode(Data(raw.utf8)))
        let update = try #require(entries.first?.unofficialUpdate)
        #expect(update.version == "1.6.1-unofficial-2.dphill")
        #expect(update.url == "https://forums.example.net/post-148313")
    }

    @Test func anUnofficialUpdateMissingItsUrlOrVersionInfersNothing() {
        // Un objet amputé ne devient pas un verdict : le bouton n'aurait pas
        // de destination, ou pas de libellé.
        let raw = """
        {
          "mods": [
            { "id": "a.b", "unofficialUpdate": { "version": "1.0.0-unofficial.1" } },
            { "id": "c.d", "unofficialUpdate": { "url": "https://example.com/c" } }
          ]
        }
        """
        let entries = PathoschildCompatibilityList.decode(Data(raw.utf8)) ?? []
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.unofficialUpdate == nil })
        #expect(PathoschildCompatibilityList.verdicts(for: ["a.b", "c.d"], from: entries).isEmpty)
    }

    // MARK: - Fins de ligne

    @Test func lineCommentsStopAtACarriageReturnToo() throws {
        // Le dump réel (919 Ko, 4 720 entrées) est en LF aujourd'hui — 0 CR.
        // Converti en CRLF, il ne se décodait **plus du tout** : en Swift
        // `\r\n` est un seul `Character`, jamais égal à `"\n"`, donc le
        // premier `//` du fichier (5e ligne) emportait tout jusqu'à la fin.
        // Zéro verdict et zéro identifiant Nexus, en silence.
        let lf = """
        {
          "mods": [
            { "id": "a.b", // Nexus, manifest
              "status": "Broken" }
          ]
        }
        """
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        let fromLF = try #require(PathoschildCompatibilityList.decode(Data(lf.utf8)))
        let fromCRLF = try #require(PathoschildCompatibilityList.decode(Data(crlf.utf8)))
        #expect(fromLF.count == 1)
        #expect(fromCRLF == fromLF)
        #expect(fromCRLF.first?.status == "Broken")
    }

    @Test func aLineCommentDoesNotEatTheRestOfACrlfFile() throws {
        // La forme exacte du dump : un commentaire en fin de ligne, suivi de
        // 4 719 autres entrées. Sur deux, on voit déjà si la suite survit.
        let text = "{\r\n\"mods\": [\r\n{ \"id\": \"a.b\" }, // note\r\n{ \"id\": \"c.d\" }\r\n]\r\n}"
        let entries = try #require(PathoschildCompatibilityList.decode(Data(text.utf8)))
        #expect(entries.map(\.id) == ["a.b", "c.d"])
    }

    // MARK: - Un 200 n'est pas une donnée

    @Test func anUnreadableBodyNeverReplacesAReadableCache() {
        // Une page d'erreur GitHub ou un portail captif : HTTP 200, corps qui
        // n'est pas du JSONC. Le cache doit survivre — c'est lui que
        // `PathoschildNexusIndex` relit hors ligne.
        let cache = Data(#"{ "mods": [ { "id": "a.b", "status": "Broken" } ] }"#.utf8)
        let outcome = PathoschildCompatibilityList.outcome(
            forPayload: Data("<html>502 Bad Gateway</html>".utf8),
            cachedPayload: { cache })
        guard case .fallback(let entries) = outcome else {
            Issue.record("attendu un repli sur le cache, obtenu \(outcome)"); return
        }
        #expect(entries.map(\.id) == ["a.b"])
    }

    @Test func aTruncatedBodyIsUnreadableToo() {
        // Un transfert coupé rend un 200 au JSON tronqué : même traitement.
        let outcome = PathoschildCompatibilityList.outcome(
            forPayload: Data(#"{ "mods": [ { "id": "a.b", "stat"#.utf8),
            cachedPayload: { nil })
        #expect(outcome == .unreadable)
    }

    @Test func areadableBodyIsTheOneThatGetsCached() {
        let outcome = PathoschildCompatibilityList.outcome(
            forPayload: Data(#"{ "mods": [ { "id": "a.b", "status": "Abandoned" } ] }"#.utf8),
            cachedPayload: { Issue.record("le cache ne doit pas être lu quand le corps se lit")
                             return nil })
        guard case .fresh(let entries) = outcome else {
            Issue.record("attendu un corps frais, obtenu \(outcome)"); return
        }
        #expect(entries.map(\.id) == ["a.b"])
    }

    @Test func anUnreadableBodyWithAnUnreadableCacheSaysSo() {
        // Le cas qui construit enfin `Failure.decoding` : elle existait dans
        // l'enum sans qu'aucun chemin ne la produise.
        #expect(PathoschildCompatibilityList.outcome(
            forPayload: Data("nope".utf8),
            cachedPayload: { Data("nope non plus".utf8) }) == .unreadable)
    }

    // MARK: - TTL

    @Test func cacheTTLIsInTheDocumentedRange() {
        // A2-T4 prescrit 6-24 h. On s'aligne sur la borne basse pour A2-T3 :
        // un dump statique change peu, mais un mod retiré du dépôt Pathoschild
        // doit cesser d'être signalé dans la journée.
        #expect(PathoschildCompatibilityList.cacheTTL == 6 * 60 * 60)
    }
}