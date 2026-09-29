import Testing
import Foundation
@testable import StarHubTHCore

struct GuidedFilesTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("guided-\(UUID().uuidString)", isDirectory: true)

    private func plan(_ id: UUID = UUID()) -> GuidedPlan {
        GuidedPlan(id: id, name: "Mesure du 29/09", role: .before, location: "Farm", pairedWith: nil,
                   createdAt: Date(timeIntervalSince1970: 1_790_000_000))
    }

    /// Clés PascalCase : c'est ce que lit `System.Text.Json` dans la sonde.
    @Test func planRoundTripsWithPascalCaseKeys() throws {
        let url = directory.appendingPathComponent("guided-plan.json")
        let written = plan()
        try written.write(to: url)
        #expect(GuidedPlan.load(from: url) == written)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(Set(object.keys) == ["Version", "Id", "Name", "Role", "Location", "CreatedAt"])
        #expect(object["Role"] as? String == "before")
        #expect(object["Version"] as? Int == 1)
    }

    /// Review Focus 3 — l'effacement ne touche qu'au plan désigné.
    @Test func removeKeepsANewerPlan() throws {
        let url = directory.appendingPathComponent("guided-plan.json")
        let old = plan(), newer = plan()
        try newer.write(to: url)
        try GuidedPlan.remove(at: url, ifId: old.id)
        #expect(GuidedPlan.load(from: url) == newer)
        try GuidedPlan.remove(at: url, ifId: newer.id)
        #expect(GuidedPlan.load(from: url) == nil)
        #expect(GuidedPlan.load(from: directory.appendingPathComponent("absent.json")) == nil)
    }

    private func line(_ id: UUID, outcome: String, kept: [String], role: String = "before",
                      paired: UUID? = nil) -> String {
        let keptJSON = kept.map { "\"\($0)\"" }.joined(separator: ",")
        let pairedJSON = paired.map { "\"\($0.uuidString)\"" } ?? "null"
        return """
        {"Version":1,"PlanId":"\(id.uuidString)","Name":"m","Role":"\(role)","PairedWith":\(pairedJSON),\
        "Session":"s","Location":"Farm","Start":\(kept.first.map { "\"\($0)\"" } ?? "null"),\
        "End":\(kept.last.map { "\"\($0)\"" } ?? "null"),"KeptAt":[\(keptJSON)],"Excluded":[],\
        "Outcome":"\(outcome)","FrameIqrShare":null,"WorkIqrShare":0.03,"GameTimeFrom":600,\
        "GameTimeTo":700,"Probe":"0.5.0","Unknown":1}
        """
    }

    /// Review Focus 2 et 5 — terminal l'emporte sur abandoned ; `+` et
    /// 7 décimales lus ; une ligne coupée comptée.
    @Test func decodePrefersTerminalLinesAndReadsProbeDates() throws {
        let a = UUID(), b = UUID()
        let at = "2026-09-29T10:01:00.1234567\\u002B02:00"
        let text = [
            line(a, outcome: "abandoned", kept: [at]),
            line(a, outcome: "stable", kept: [at]),
            line(a, outcome: "abandoned", kept: [at]),
            line(b, outcome: "abandoned", kept: []),
            "{\"PlanId\":",
        ].joined(separator: "\n")
        let result = GuidedMeasurementsFile.decode(Data(text.utf8))
        #expect(result.unreadable == 1)
        #expect(result.measurements.count == 1)   // b : abandonnée sans minute, rien à montrer
        let m = try #require(result.measurements.first)
        #expect(m.id == a && m.outcome == .stable && m.role == .before && m.location == "Farm")
        #expect(m.keptAt == [try #require(ProbeDate.parse("2026-09-29T10:01:00.1234567+02:00"))])
        #expect(m.start == m.end)
    }

    /// Une ligne d'une sonde plus récente (issue inconnue) n'est pas une
    /// ligne abîmée : ignorée, pas comptée « illisible ».
    @Test func unknownOutcomeIsSkippedNotCountedUnreadable() {
        let at = "2026-09-29T10:01:00.1234567+02:00"
        let result = GuidedMeasurementsFile.decode(Data(line(UUID(), outcome: "paused", kept: [at]).utf8))
        #expect(result.measurements.isEmpty)
        #expect(result.unreadable == 0)
    }

    /// Un effacement qui échoue se dit : « Abandonner » ne passe pas en
    /// silence à « rien en attente » quand le plan est toujours sur disque.
    @Test func removeFailureThrows() throws {
        let url = directory.appendingPathComponent("guided-plan.json")
        let written = plan()
        try written.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        #expect(throws: (any Error).self) { try GuidedPlan.remove(at: url, ifId: written.id) }
        #expect(GuidedPlan.load(from: url) == written)
    }
}
