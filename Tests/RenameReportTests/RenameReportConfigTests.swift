import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct RenameReportConfigTests {

    @Test func valueMovesAndOldKeyLeaves() throws {
        let text = #"{"EnableBeta":true,"Nested":{"a":1}}"#
        let (out, applied) = RenameReport.applyToConfig(
            text, pairs: [RenamePair(oldKey: "EnableBeta", newKey: "BetaEnabled")])
        #expect(applied.count == 1)
        let obj = try JSONSerialization.jsonObject(with: Data(out.utf8)) as! [String: Any]
        #expect(obj["BetaEnabled"] as? Bool == true)
        #expect(obj["Nested"] as? [String: Int] == ["a": 1])
        #expect(obj["EnableBeta"] == nil)
    }

    @Test func abstainsWhenNewKeyExists() throws {
        let text = #"{"old":"x","new":0}"#
        let (out, applied) = RenameReport.applyToConfig(
            text, pairs: [RenamePair(oldKey: "old", newKey: "new")])
        #expect(applied.isEmpty)
        #expect(out == text)
    }
}
