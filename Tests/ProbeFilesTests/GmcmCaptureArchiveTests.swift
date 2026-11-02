import Testing
import Foundation
@testable import StarHubTHCore

/// La capture de la sonde est réécrite à chaque session et ne porte que les
/// mods chargés : sans archive, mettre un mod en pause effaçait ses libellés
/// et sa mise en page de l'éditeur. L'archive garde la dernière capture de
/// chaque mod.
struct GmcmCaptureArchiveTests {
    private func capture(at date: String, _ mods: [(id: String, version: String, label: String)]) throws -> GmcmCapture {
        let json: [String: Any] = [
            "CapturedAt": date, "Language": "fr",
            "Mods": mods.map { mod -> [String: Any] in
                ["UniqueID": mod.id, "Name": mod.id, "Version": mod.version,
                 "ConfigSnapshot": #"{"Enabled": true}"#,
                 "Options": [["Kind": "SimpleModOption", "Name": mod.label, "ValueType": "Boolean",
                              "Value": "True", "AccessPath": ["Config", "Enabled"],
                              "ClosureStrings": [String]()]]]
            },
        ]
        return try #require(GmcmCapture.decode(try JSONSerialization.data(withJSONObject: json)))
    }

    private func label(_ archive: GmcmCaptureArchive, _ id: String, _ version: String) -> String? {
        archive.options(forMod: id, installedVersion: version)?.entry(for: ["Enabled"])?.label
    }

    @Test func aModMissingFromTheNextCaptureIsKept() throws {
        var archive = GmcmCaptureArchive()
        #expect(archive.absorb(try capture(at: "2026-11-01T10:00:00+01:00", [("a.Pure", "1.0.7", "Pure"), ("b.Other", "2.0", "Other")])))
        #expect(archive.absorb(try capture(at: "2026-11-02T10:00:00+01:00", [("b.Other", "2.0", "Other bis")])))
        #expect(label(archive, "a.pure", "1.0.7") == "Pure")
        #expect(label(archive, "b.Other", "2.0") == "Other bis")
    }

    /// Une nouvelle version remplace l'ancienne : ses clés ont pu bouger.
    @Test func aNewerVersionReplacesTheOldOne() throws {
        var archive = GmcmCaptureArchive()
        _ = archive.absorb(try capture(at: "2026-11-01T10:00:00+01:00", [("a.Pure", "1.0.6", "Old")]))
        _ = archive.absorb(try capture(at: "2026-11-02T10:00:00+01:00", [("a.Pure", "1.0.7", "New")]))
        #expect(label(archive, "a.Pure", "1.0.6") == nil)
        #expect(label(archive, "a.Pure", "1.0.7") == "New")
    }

    /// Relire une capture déjà absorbée, ou une plus ancienne, ne change rien.
    @Test func anOlderCaptureNeverWins() throws {
        var archive = GmcmCaptureArchive()
        _ = archive.absorb(try capture(at: "2026-11-02T10:00:00+01:00", [("a.Pure", "1.0.7", "New")]))
        #expect(!archive.absorb(try capture(at: "2026-11-02T10:00:00+01:00", [("a.Pure", "1.0.7", "New")])))
        #expect(!archive.absorb(try capture(at: "2026-11-01T10:00:00+01:00", [("a.Pure", "1.0.6", "Old")])))
        #expect(label(archive, "a.Pure", "1.0.7") == "New")
    }

    @Test func itSurvivesASaveAndALoad() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("gmcm-capture-archive.json")
        var archive = GmcmCaptureArchive()
        _ = archive.absorb(try capture(at: "2026-11-02T10:00:00+01:00", [("a.Pure", "1.0.7", "Pure")]))
        try archive.save(to: url)
        #expect(label(GmcmCaptureArchive.load(from: url), "a.Pure", "1.0.7") == "Pure")
        #expect(GmcmCaptureArchive.load(from: url.appendingPathExtension("absent")).isEmpty)
    }

    /// Écrit par une version plus récente de l'app : lu, jamais réécrit.
    @Test func aFutureFormatIsNotOverwritten() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        let future = Data(#"{"version": 99, "mods": {}}"#.utf8)
        try future.write(to: url)
        var archive = GmcmCaptureArchive.load(from: url)
        _ = archive.absorb(try capture(at: "2026-11-02T10:00:00+01:00", [("a.Pure", "1.0.7", "Pure")]))
        try archive.save(to: url)
        #expect(try Data(contentsOf: url) == future)
    }
}
