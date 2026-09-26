import Testing
import Foundation
@testable import StarHubTHCore

struct ProbeFilesCacheTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProbeFilesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func defaultDirectoryIsTheProbeModData() {
        #expect(ProbeFiles.defaultDirectory.path.hasSuffix(
            ".config/StardewValley/ModData/mrbabilo.StarHubFR.Probe"))
    }

    /// Aucun fichier (tout utilisateur sans la sonde) : pas de carte, pas de
    /// session, et le catalogue décompilé tel quel.
    @Test func noProbeFilesMeansTheDecompiledCatalog() throws {
        let files = ProbeFiles(directory: try tempDirectory())
        #expect(files.harmonyMap() == nil)
        #expect(files.sessions().sessions.isEmpty)
        let cache = ProbeHarmonyMapCache(files: files)
        #expect(cache.performanceCatalog() == PerformanceOverlap.catalog)
    }

    @Test func filesAreReadFromTheDirectory() throws {
        let directory = try tempDirectory()
        for name in ["harmony-map.json", "timings.jsonl", "mod-costs.jsonl"] {
            try Fixture.data(name).write(to: directory.appendingPathComponent(name))
        }
        let files = ProbeFiles(directory: directory)
        #expect(files.harmonyMap()?.mods.count == 291)
        #expect(files.sessions().sessions.count == 4)
    }

    /// Une nouvelle session réécrit la carte pendant que l'app tourne : relue.
    /// Devenue illisible : le catalogue, jamais l'ancienne carte.
    @Test func theCacheFollowsTheFileAndFallsBackWhenItBreaks() throws {
        let directory = try tempDirectory()
        let files = ProbeFiles(directory: directory)
        let cache = ProbeHarmonyMapCache(files: files)
        #expect(cache.harmonyMap() == nil)

        try Fixture.data("harmony-map.json").write(to: files.harmonyMapURL)
        #expect(cache.harmonyMap()?.capturedAt == "2026-09-26T20:40:00.3802060+02:00")

        try Data("{".utf8).write(to: files.harmonyMapURL)
        #expect(cache.harmonyMap() == nil)
        #expect(cache.performanceCatalog() == PerformanceOverlap.catalog)
    }
}
