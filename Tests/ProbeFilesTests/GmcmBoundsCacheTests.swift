import Testing
import Foundation
@testable import StarHubTHCore

struct GmcmBoundsCacheTests {
    private typealias Bounds = GmcmModOptions.Bounds

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GmcmCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// `String(Double)` rend la plus courte forme exacte : sans arrondi, un
    /// pas de 0,05 écrit `0.15000000000000002` dans config.json.
    @Test func snappingWritesShortLiterals() {
        let volume = Bounds(min: 0, max: 1.5, step: 0.05)
        #expect(String(volume.snapped(0.1 + 0.05, integer: false)) == "0.15")
        #expect(String(volume.snapped(0.7349, integer: false)) == "0.75")
        let buff = Bounds(min: 1, max: 3, step: 0.05)
        #expect(String(buff.snapped(1.7512, integer: false)) == "1.75")
    }

    @Test func snappingFollowsTheGridFromMin() {
        #expect(Bounds(min: 256, max: 4096, step: 256).snapped(700, integer: true) == 768)
        #expect(Bounds(min: 1, max: 4.5, step: 0.5).snapped(2.2, integer: false) == 2)
        #expect(Bounds(min: -64, max: 64, step: 4).snapped(-10, integer: false) == -8)
    }

    @Test func snappingWithoutStep() {
        #expect(Bounds(min: 0, max: 255, step: nil).snapped(127.6, integer: true) == 128)
        #expect(String(Bounds(min: 0, max: 1, step: nil).snapped(0.123456, integer: false)) == "0.12")
    }

    @Test func snappingStaysInBounds() {
        // 10 / 4 = 2,5 : la grille arrondit à 12, les bornes ramènent à 10.
        let bounds = Bounds(min: 0, max: 10, step: 4)
        #expect(bounds.snapped(11, integer: true) == 10)
        #expect(bounds.snapped(-5, integer: true) == 0)
        #expect(Bounds(min: 0, max: 10, step: 3).snapped(10, integer: true) == 9)
    }

    @Test func theCaptureIsReadFromTheDirectory() throws {
        let directory = try tempDirectory()
        let files = ProbeFiles(directory: directory)
        #expect(files.gmcmCapture() == nil)
        try Fixture.data("gmcm-options.json").write(to: files.gmcmOptionsURL)
        #expect(files.gmcmCapture()?.language == "fr")
    }

    /// Nouvelle session : relue. Devenue illisible : rien, jamais l'ancienne.
    @Test func theCacheFollowsTheFile() throws {
        let directory = try tempDirectory()
        let files = ProbeFiles(directory: directory)
        let cache = GmcmCaptureCache(files: files)
        #expect(cache.capture() == nil)

        try Fixture.data("gmcm-options.json").write(to: files.gmcmOptionsURL)
        #expect(cache.options(forMod: "palmhacker13.UltraSmooth", installedVersion: "2.3.8")?.count == 60)

        try Data("{".utf8).write(to: files.gmcmOptionsURL)
        #expect(cache.capture() == nil)
        #expect(cache.options(forMod: "palmhacker13.UltraSmooth", installedVersion: "2.3.8") == nil)
    }
}
