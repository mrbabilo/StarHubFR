import Foundation
import Testing
@testable import StarHubTHCore

/// A3-T7 — la fiche par l'API v2, sans clé. Les réponses sont réelles
/// (`NexusModDetailV2Fixtures`) ; la règle de fusion a été mesurée contre la
/// v1 sur 31 fiches : 609 versions sur 609 identiques.
@Suite struct NexusModDetailV2Tests {

    private func decode(_ json: String) -> ModDetailRaw? {
        try? NexusModDetailV2.decode(Data(json.utf8)).get()
    }

    private func files(_ json: String) -> [[String: Any]] {
        let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        return ((root?["data"] as? [String: Any])?["modFiles"] as? [[String: Any]]) ?? []
    }

    @Test func decodesDescriptionAndChangelog() throws {
        let raw = try #require(decode(NexusModDetailV2Fixtures.zebrusCore))
        #expect(raw.description.hasPrefix("[b][color=#ff7700][size=3]I use AI"))
        // Format v1 (`formatChangelogs`) : la plus récente en tête.
        #expect(raw.changelog.hasPrefix("**1.10.0**\n- "))
    }

    /// Deux fichiers ARCHIVED en 1.9.0, même journal de 4 lignes : il compte
    /// une fois, pas huit lignes.
    @Test func identicalChangelogsOfTheSameVersionCountOnce() {
        let merged = NexusModDetailV2.mergeChangelogs(files(NexusModDetailV2Fixtures.zebrusCore))
        #expect(merged["1.9.0"]?.count == 4)
        #expect(merged.count == 16)
    }

    /// SVE 1.14.14 : 23 lignes dont des « . » répétés comme séparateurs, sur
    /// quatre fichiers. La v1 garde les 23 ; un dédoublonnage ligne à ligne
    /// en perdrait — le défaut qu'a trouvé la mesure.
    @Test func legitimatelyRepeatedLinesSurvive() {
        let merged = NexusModDetailV2.mergeChangelogs(files(NexusModDetailV2Fixtures.sveExcerpt))
        #expect(merged["1.14.14"]?.count == 23)
        #expect(merged["1.15.11"]?.count == 30)
    }

    /// Même version, journaux différents : les lignes neuves s'ajoutent, dans
    /// l'ordre des dates, sans répéter celles déjà vues.
    @Test func differingChangelogsOfTheSameVersionMerge() {
        let merged = NexusModDetailV2.mergeChangelogs([
            ["version": "1.0", "date": 2, "changelogText": ["b", "c"]],
            ["version": "1.0", "date": 1, "changelogText": ["a", "b"]],
            ["version": "", "date": 3, "changelogText": ["sans version"]],
            ["version": "2.0", "date": 4, "changelogText": []],
        ])
        #expect(merged == ["1.0": ["a", "b", "c"]])
    }

    @Test func serviceErrorsWin() {
        let json = #"{"errors":[{"message":"boom"}],"data":null}"#
        #expect(throws: NexusModSearch.Failure.service("boom")) {
            try NexusModDetailV2.decode(Data(json.utf8)).get()
        }
    }

    /// Mod inconnu : la v2 rend une liste vide, pas une erreur — pas de
    /// description, donc échec, et le repli local de l'appelant tient.
    @Test func noDescriptionIsAFailure() {
        let json = #"{"data":{"mods":{"nodes":[]},"modFiles":[]}}"#
        #expect(decode(json) == nil)
    }

    @Test func bodyCarriesTheModIdAsVariables() throws {
        let body = try #require(NexusModDetailV2.body(modId: 3753, gameId: 1303))
        let root = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let variables = try #require(root["variables"] as? [String: String])
        #expect(variables == ["game": "1303", "id": "3753", "modId": "3753", "gameId": "1303"])
    }
}
