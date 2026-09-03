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