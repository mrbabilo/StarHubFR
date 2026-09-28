import Testing
import Foundation
@testable import StarHubTHCore

struct ProbeSessionsIndexTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("probe-index-\(UUID().uuidString)", isDirectory: true)

    private func write(_ name: String, _ lines: [String]) throws -> ProbeFiles {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").appending("\n")
            .write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        return ProbeFiles(directory: directory)
    }

    private func timingLine(session: String, at: String) -> String {
        "{\"Session\":\"\(session)\",\"At\":\"\(at)\",\"WallSeconds\":60,\"Fps\":30," +
        "\"FrameInterval\":{\"Count\":45,\"Avg\":30,\"P50\":30,\"P99\":50,\"Max\":60}," +
        "\"InactiveTicks\":0,\"HeapMB\":4000,\"LoadedMods\":289,\"Location\":\"Farm\"}"
    }

    @Test func keepsOnlyWantedSessions() throws {
        let files = try write("timings.jsonl", [
            timingLine(session: "sA", at: "2026-09-28T10:00:00.0000000+02:00"),
            timingLine(session: "sB", at: "2026-09-28T11:00:00.0000000+02:00"),
        ])
        let result = ProbeSessionsIndex(files: files).sessions(keeping: ["sB"])
        #expect(result.sessions.map(\.id) == ["sB"])
        #expect(result.sessions.first?.minutes.count == 1)
    }

    /// Les vrais fichiers : `timings.jsonl` échappe le `+` du fuseau
    /// (`+`), `mod-costs.jsonl` non. L'identifiant indexé doit être
    /// celui que le décodage complet rend, sinon toutes les minutes réelles
    /// disparaissent en silence.
    @Test func realFilesMatchTheFullDecode() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["timings.jsonl", "mod-costs.jsonl"] {
            try Fixture.data(name).write(to: directory.appendingPathComponent(name))
        }
        let files = ProbeFiles(directory: directory)
        let full = files.sessions()
        let wanted = try #require(full.sessions.first { $0.id.hasPrefix("2026-09-26T20:30") })
        let result = ProbeSessionsIndex(files: files).sessions(keeping: [wanted.id])
        #expect(result.sessions == [wanted])
        #expect(result.sessions.first?.minutes.count == 8)
        #expect(result.sessions.first?.costs.count == 8)
        #expect(ProbeSessionsIndex(files: files).sessions(keeping: nil).sessions == full.sessions)
    }

    /// Une ligne coupée dans le préfixe lui-même : comptée, jamais levée.
    @Test func truncatedPrefixCountedUnreadable() throws {
        let files = try write("timings.jsonl", [
            timingLine(session: "sA", at: "2026-09-28T10:00:00.0000000+02:00"),
            "{\"Sess",
        ])
        let result = ProbeSessionsIndex(files: files).sessions(keeping: ["sA"])
        #expect(result.sessions.count == 1)
        #expect(result.unreadableLines == 1)
    }

    /// Le cache suit taille + date du fichier : une réécriture change le résultat.
    @Test func cacheFollowsFileStamp() throws {
        var lines = [timingLine(session: "sA", at: "2026-09-28T10:00:00.0000000+02:00")]
        let files = try write("timings.jsonl", lines)
        let index = ProbeSessionsIndex(files: files)
        #expect(index.sessions(keeping: nil).sessions.count == 1)
        lines.append(timingLine(session: "sB", at: "2026-09-28T11:00:00.0000000+02:00"))
        try lines.joined(separator: "\n").appending("\n")
            .write(to: files.timingsURL, atomically: true, encoding: .utf8)
        #expect(index.sessions(keeping: nil).sessions.count == 2)
    }
}
