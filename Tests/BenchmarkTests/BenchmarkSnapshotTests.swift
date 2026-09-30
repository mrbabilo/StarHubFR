import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct BenchmarkSnapshotTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func snapshotRoundTripsAndClears() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let snap = BenchmarkSnapshot(enabledFolders: ["A", "B"], activeProfileId: UUID(),
                                     saveCopies: ["/tmp/Saves/TestOK_1_bench"], originals: [],
                                     startedAt: Date(timeIntervalSince1970: 1_790_000_000))
        BenchmarkSnapshotStore.save(snap, in: dir)
        #expect(BenchmarkSnapshotStore.load(from: dir) == snap)
        BenchmarkSnapshotStore.clear(in: dir)
        #expect(BenchmarkSnapshotStore.load(from: dir) == nil)
        #expect(BenchmarkSnapshotStore.load(from: nil) == nil)
    }

    /// Review Focus 2 : une sauvegarde d'origine modifiée pendant la série se voit.
    @Test func aTouchedOriginalIsReported() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let untouched = dir.appendingPathComponent("A"), touched = dir.appendingPathComponent("B"),
            removed = dir.appendingPathComponent("C")
        for url in [untouched, touched, removed] { try Data("x".utf8).write(to: url) }
        let stamps = try [untouched, touched, removed].map { try #require(SaveFileStamp.read($0)) }
        try Data("xy".utf8).write(to: touched)
        try FileManager.default.removeItem(at: removed)
        #expect(BenchmarkSaveCheck.changed(stamps) == [touched.path, removed.path])
    }

    @Test func aMissingFileHasNoStamp() {
        #expect(SaveFileStamp.read(URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")) == nil)
    }
}
