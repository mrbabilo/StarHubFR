import Foundation
import Testing
@testable import StarHubTHCore

/// A3-T8 — approuver un mod sur Nexus. Chemins : spécification officielle de
/// l'API v1 ; corps et réponses : `IEndorsement`/`IEndorseResponse` du client
/// officiel `node-nexus-api`. ⚠️ **Non mesuré en direct** (un essai approuverait
/// un vrai mod) — d'où l'issue `unknown` qui rend toujours le brut.
@Suite struct NexusEndorsementTests {

    @Test func statusesKeepOnlyStardewAndFoldCase() throws {
        let body = #"""
        [{"mod_id": 1915, "domain_name": "stardewvalley", "date": 1600000000, "version": "2.0", "status": "Endorsed"},
         {"mod_id": 5098, "domain_name": "StardewValley", "status": "ABSTAINED"},
         {"mod_id": 42,   "domain_name": "skyrim", "status": "Endorsed"},
         {"mod_id": 7,    "domain_name": "stardewvalley", "status": "Undecided"}]
        """#
        let map = try #require(NexusEndorsement.statuses(from: Data(body.utf8)))
        #expect(map == [1915: .endorsed, 5098: .abstained, 7: .undecided])
    }

    @Test func statusesRefuseAnUnreadableBody() {
        #expect(NexusEndorsement.statuses(from: Data("<html>".utf8)) == nil)
    }

    @Test func outcomesReadStatusAndTypedErrors() {
        func outcome(_ json: String, _ code: Int = 200) -> NexusEndorsement.Outcome {
            NexusEndorsement.outcome(from: Data(json.utf8), httpStatus: code)
        }
        #expect(outcome(#"{"message": "Updated to: Endorsed", "status": "Endorsed"}"#) == .endorsed)
        #expect(outcome(#"{"status": "abstained"}"#) == .abstained)
        #expect(outcome(#"{"status": "Error", "message": "IS_OWN_MOD"}"#, 400) == .isOwnMod)
        #expect(outcome(#"{"status": "Error", "message": "TOO_SOON_AFTER_DOWNLOAD"}"#, 400) == .tooSoonAfterDownload)
        #expect(outcome(#"{"status": "Error", "message": "NOT_DOWNLOADED_MOD"}"#, 403) == .notDownloaded)
    }

    @Test func anythingElseIsUnknownWithCodeAndRawText() {
        #expect(NexusEndorsement.outcome(from: Data(#"{"status": "Error", "message": "SOMETHING_NEW"}"#.utf8), httpStatus: 422)
                == .unknown(httpStatus: 422, message: "SOMETHING_NEW"))
        #expect(NexusEndorsement.outcome(from: Data("Bad Gateway".utf8), httpStatus: 502)
                == .unknown(httpStatus: 502, message: "Bad Gateway"))
    }

    @Test func bodyCarriesTheInstalledVersion() throws {
        let object = try JSONSerialization.jsonObject(with: NexusEndorsement.body(version: "1.6.2+beta")) as? [String: String]
        #expect(object == ["Version": "1.6.2+beta"])
        #expect(String(decoding: NexusEndorsement.body(version: ""), as: UTF8.self) == "{}")
    }

    @Test func anErrorFieldIsReadWhenMessageIsAbsent() {
        #expect(NexusEndorsement.outcome(from: Data(#"{"error": "NOT_DOWNLOADED_MOD"}"#.utf8), httpStatus: 403)
                == .notDownloaded)
    }

    @Test func pathsFollowTheSpecification() {
        #expect(NexusEndorsement.listPath == "/user/endorsements.json")
        #expect(NexusEndorsement.path(modId: 1915, endorse: true) == "/games/stardewvalley/mods/1915/endorse.json")
        #expect(NexusEndorsement.path(modId: 1915, endorse: false) == "/games/stardewvalley/mods/1915/abstain.json")
    }
}
